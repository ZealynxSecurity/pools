// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {PoolTokensDeployer} from "deploy/PoolTokens.sol";
import {IPoolDeployer} from "src/Types/Interfaces/IPoolDeployer.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {ROUTE_ACCOUNTING_DEPLOYER} from "src/Constants/Routes.sol";
import {InvalidParams, InvalidState, Unauthorized} from "src/Errors.sol";

string constant IMPLEMENTATION = "IMPLEMENTATION";
string constant ACCOUNTING = "ACCOUNTING";

contract PoolFactory is IPoolFactory, RouterAware, Operatable {
  /**
   * @notice The PoolFactoryAdmin can change the treasury fee up to the MAX_TREASURY_FEE
   * @dev treasury fee is denominated by 1e18, in other words, 1e17 is 10% fee
   */
  uint256 public constant MAX_TREASURY_FEE = 1e17;
  uint256 public treasuryFeeRate;
  uint256 public feeThreshold;
  IERC20 public asset;
  address[] public allPools;
  // poolExists
  mapping(bytes32 => bool) public exists;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  constructor(
    IERC20 _asset,
    uint256 _treasuryFeeRate,
    uint256 _feeThreshold,
    address _owner,
    address _operator
  ) Operatable(_owner, _operator) {
    asset = _asset;
    treasuryFeeRate = _treasuryFeeRate;
    feeThreshold = _feeThreshold;
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  /**
   * @dev Creates a new pool
   * @param name The name of the pool
   * @param symbol The symbol of the pool
   * @param owner The owner of the pool
   * @param operator The operator of the pool
   * @param implementation The implementation of the pool
   * @return pool The address of the new pool
   */
  function createPool(
    string memory name,
    string memory symbol,
    address owner,
    address operator,
    address implementation
  ) external onlyOwnerOperator returns (IPool pool) {
    if (!isPoolImplementation(implementation)) revert InvalidParams();
    if (operator == address(0)) revert InvalidParams();

    IPoolDeployer deployer = IPoolDeployer(IRouter(router).getRoute(ROUTE_ACCOUNTING_DEPLOYER));

    uint256 poolID = allPools.length;
    address stakingAsset = address(asset);

    // Create custom ERC20 for the pools
    (
      address shareToken,
      address iouToken
    ) = PoolTokensDeployer.deploy(
      router,
      poolID,
      name,
      symbol
    );

    // deploy a new Pool Accounting instance
    pool = deployer.deploy(
      owner,
      operator,
      poolID,
      router,
      implementation,
      stakingAsset,
      shareToken,
      // start with no offramp
      address(0),
      iouToken,
      0
    );
    // add the pool to the list of all pools
    allPools.push(address(pool));
    // cache the new pool in storage
    exists[createKey(ACCOUNTING, address(pool))] = true;
  }

  /**
   * @dev upgrades a Pool Accounting instance
   * @param poolId The id of the pool to upgrade
   */
  function upgradePool(
    uint256 poolId
  ) external returns (IPool newPool) {
    IPool oldPool = IPool(allPools[poolId]);
    // only the Pool's owner or operator can upgrade
    if (IAuth(address(oldPool)).owner() != msg.sender && IAuth(address(oldPool)).operator() != msg.sender) revert Unauthorized();
    // the pool must be shutting down (deposits disabled) to upgrade
    if (!oldPool.isShuttingDown()) revert InvalidState();

    IPoolDeployer deployer = IPoolDeployer(IRouter(router).getRoute(ROUTE_ACCOUNTING_DEPLOYER));
    // deploy a new instance of PoolAccounting
    newPool = deployer.deploy(
      IAuth(address(oldPool)).owner(),
      IAuth(address(oldPool)).operator(),
      poolId,
      router,
      address(oldPool.implementation()),
      address(oldPool.asset()),
      address(oldPool.share()),
      address(oldPool.ramp()),
      address(oldPool.iou()),
      oldPool.minimumLiquidity()
    );
    // Update the pool to exist before we decomission the old pool so transfer checks will succeed
    allPools[poolId] = address(newPool);
    exists[createKey(ACCOUNTING, address(newPool))] = true;
    uint256 borrowedAmount = oldPool.decommissionPool(newPool);
    // change update the pointer in factory storage
    // reset pool mappings
    exists[createKey(ACCOUNTING, address(oldPool))] = false;
    // update the accounting in the new pool
    newPool.jumpStartTotalBorrowed(borrowedAmount);
  }

  /**
   * @dev Returns if a Pool Accounting instance exists
   * @param pool The address of the pool
   */
  function isPool(address pool) external view returns (bool) {
    return exists[createKey(ACCOUNTING, pool)];
  }

  /**
   * @dev Returns if a Pool Implementation instance exists
   * @param implementation The address of the implementation
   */
  function isPoolImplementation(address implementation) public view returns (bool) {
    return exists[createKey(IMPLEMENTATION, implementation)];
  }

  /**
   * @dev Approves a new Pool Implementation
   * @notice only the factory admin can approve new implementations
   */
  function approveImplementation(address implementation) external onlyOwnerOperator {
    exists[createKey(IMPLEMENTATION, address(implementation))] = true;
  }

  /**
   * @dev Revokes an Implementation
   * @notice only the factory admin can revoke an implementation
   *
   * TODO: Not sure about side effects of removing live versions? Should be safe - deprecation
   */
  function revokeImplementation(address implementation) external onlyOwnerOperator {
    exists[createKey(IMPLEMENTATION, address(implementation))] = false;
  }

  /**
   * @dev Sets the treasury fee rate
   */
  function setTreasuryFeeRate(uint256 newFeeRate) external onlyOwnerOperator {
    require(newFeeRate <= MAX_TREASURY_FEE, "Pool: Fee too high");
    treasuryFeeRate = newFeeRate;
  }

  /**
   * @dev Sets the treasury fee threshold
   * The fee threshold is the amount of assets to accure in a Pool until transferring the fee to the treasury
   */
  function setFeeThreshold(uint256 newThreshold) external onlyOwnerOperator {
    feeThreshold = newThreshold;
  }

  function createKey(string memory partitionKey, address entity) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, entity));
  }
}
