// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {PoolAccountingDeployer} from "deploy/PoolAccounting.sol";
import {PoolTokensDeployer} from "deploy/PoolTokens.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {ROUTE_TREASURY} from "src/Constants/Routes.sol";

string constant IMPLEMENTATION = "IMPLEMENTATION";
string constant TEMPLATE = "TEMPLATE";
string constant ACCOUNTING = "ACCOUNTING";

contract PoolFactory is IPoolFactory, RouterAware {
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

  modifier requiresAuth() virtual {
    AuthController.requiresSubAuth(router, address(this));
    _;
  }

  constructor(
    IERC20 _asset,
    uint256 _treasuryFeeRate,
    uint256 _feeThreshold
  ) {
    asset = _asset;
    treasuryFeeRate = _treasuryFeeRate;
    feeThreshold = _feeThreshold;
  }

  function createSymbol() internal view returns (string memory) {
    bytes memory b;
    b = abi.encodePacked("P");
    b = abi.encodePacked(b, Strings.toString(allPools.length));
    b = abi.encodePacked(b, "GLIF");

    return string(b);
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  /**
   * @dev Creates a new pool
   * @param name The name of the pool
   * @param symbol The symbol of the pool
   * @param operator The operator of the pool
   * @param implementation The implementation of the pool
   * @param template The template of the pool
   * @return pool The address of the new pool
   */
  function createPool(
    string memory name,
    string memory symbol,
    address operator,
    address implementation,
    address template
  ) external requiresAuth returns (IPool pool) {
    require(isPoolImplementation(implementation), "Pool: Implementation not approved");
    require(isPoolTemplate(template), "Pool: Template not approved");
    require(operator != address(0), "Pool: Operator cannot be 0 address");

    uint256 poolID = allPools.length;
    address stakingAsset = address(asset);

    // Create custom ERC20 for the pools
    // TODO: Token naming - https://github.com/glif-confidential/pools/issues/223
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
    pool = PoolAccountingDeployer.deploy(
      poolID,
      router,
      implementation,
      stakingAsset,
      shareToken,
      template,
      // start with no offramp
      address(0),
      iouToken,
      0
    );
    // add the pool to the list of all pools
    allPools.push(address(pool));
    // cache the new pool in storage
    exists[createKey(ACCOUNTING, address(pool))] = true;
    // grant the necessary pool roles
    AuthController.initPoolRoles(router, address(pool), operator, address(this));
  }

  /**
   * @dev upgrades a Pool Accounting instance
   * @param poolId The id of the pool to upgrade
   */
  function upgradePool(
    uint256 poolId
  ) external returns (IPool newPool) {
    IPool oldPool = IPool(allPools[poolId]);

    IMultiRolesAuthority authority = IMultiRolesAuthority(
     address(AuthController.getSubAuthority(router, address(oldPool)))
    );

    // only the Pool's operator can upgrade
    require(
      AuthController.canUpgradePool(msg.sender, authority),
      "Pool: Only Pool operator can upgrade"
    );
    // the pool must be shutting down (deposits disabled) to upgrade
    require(oldPool.isShuttingDown(), "Pool: Not shutting down");
    // deploy a new instance of PoolAccounting
    newPool = PoolAccountingDeployer.deploy(
      poolId,
      router,
      address(oldPool.implementation()),
      address(oldPool.asset()),
      address(oldPool.share()),
      address(oldPool.template()),
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
    // update the roles of the new pool
    AuthController.upgradePoolRoles(router, address(newPool), address(oldPool), authority);
  }

  /**
   * @dev Returns if a Pool Accounting instance exists
   * @param pool The address of the pool
   */
  function isPool(address pool) external view returns (bool) {
    return exists[createKey(ACCOUNTING, pool)];
  }

  /**
   * @dev Returns if a Pool Template instance exists
   * @param template The address of the template
   */
  function isPoolTemplate(address template) public view returns (bool) {
    return exists[createKey(TEMPLATE, template)];
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
  function approveImplementation(address implementation) external requiresAuth {
    exists[createKey(IMPLEMENTATION, address(implementation))] = true;
  }

  /**
   * @dev Approves a new Pool Template
   * @notice only the factory admin can approve new templates
   */
  function approveTemplate(address template) external requiresAuth {
    exists[createKey(TEMPLATE, address(template))] = true;
  }

  /**
   * @dev Revokes an Implementation
   * @notice only the factory admin can revoke an implementation
   *
   * TODO: Not sure about side effects of removing live versions? Should be safe - deprecation
   */
  function revokeImplementation(address implementation) external requiresAuth {
    exists[createKey(IMPLEMENTATION, address(implementation))] = false;
  }

  /**
   * @dev Revokes a Template
   * @notice only the factory admin can revoke a template
   */
  function revokeTemplate(address template) external requiresAuth {
    exists[createKey(TEMPLATE, address(template))] = false;
  }

  /**
   * @dev Sets the treasury fee rate
   * @notice only the factory admin can revoke a template
   */
  function setTreasuryFeeRate(uint256 newFeeRate) external requiresAuth {
    require(newFeeRate <= MAX_TREASURY_FEE, "Pool: Fee too high");
    treasuryFeeRate = newFeeRate;
  }

  /**
   * @dev Sets the treasury fee threshold
   * @notice only the factory admin can revoke a template
   * The fee threshold is the amount of assets to accure in a Pool until transferring the fee to the treasury
   */
  function setFeeThreshold(uint256 newThreshold) external requiresAuth {
    feeThreshold = newThreshold;
  }

  function createKey(string memory partitionKey, address entity) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, entity));
  }
}
