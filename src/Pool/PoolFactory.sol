// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IPoolDeployer} from "src/Types/Interfaces/IPoolDeployer.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {InvalidParams, InvalidState, Unauthorized} from "src/Errors.sol";

contract PoolFactory is IPoolFactory, Operatable {
  /**
   * @notice The PoolFactoryAdmin can change the treasury fee up to the MAX_TREASURY_FEE
   * @dev treasury fee is denominated by 1e18, in other words, 1e17 is 10% fee
   */
  uint256 public constant MAX_TREASURY_FEE = 1e17;
  uint256 public treasuryFeeRate;
  uint256 public feeThreshold;
  IERC20 public asset;
  address[] public allPools;
  address public router;
  // poolExists
  mapping(address => bool) internal exists;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  constructor(
    IERC20 _asset,
    uint256 _treasuryFeeRate,
    uint256 _feeThreshold,
    address _owner,
    address _operator,
    address _router
  ) Operatable(_owner, _operator) {
    asset = _asset;
    treasuryFeeRate = _treasuryFeeRate;
    feeThreshold = _feeThreshold;
    router = _router;
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  /**
   * @dev Creates a new pool
   * @param pool The new pool instance
   */
  function attachPool(
    IPool pool
  ) external onlyOwnerOperator {
    // add the pool to the list of all pools
    allPools.push(address(pool));
    // cache the new pool in storage
    exists[address(pool)] = true;
  }

  /**
   * @notice upgrades a Pool Accounting instance
   * @param newPool The address of the pool to upgrade
   *
   * @dev only the Pool Factory owner or operator can upgrade pools
   */
  function upgradePool(
    IPool newPool
  ) external onlyOwnerOperator {
    uint256 poolID = newPool.id();
    IPool oldPool = IPool(allPools[poolID]);

    // the pool must be shutting down (deposits disabled) to upgrade
    if (!oldPool.isShuttingDown()) revert InvalidState();

    // Update the pool to exist before we decomission the old pool so transfer checks will succeed
    allPools[poolID] = address(newPool);
    exists[address(newPool)] = true;
    uint256 borrowedAmount = oldPool.decommissionPool(newPool);
    // change update the pointer in factory storage
    // reset pool mappings
    exists[address(oldPool)] = false;
    // update the accounting in the new pool
    newPool.jumpStartTotalBorrowed(borrowedAmount);
  }

  /**
   * @dev Returns if a Pool Accounting instance exists
   * @param pool The address of the pool
   */
  function isPool(address pool) external view returns (bool) {
    return exists[pool];
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
