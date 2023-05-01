// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IPoolDeployer} from "src/Types/Interfaces/IPoolDeployer.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";

contract PoolRegistry is IPoolRegistry, Ownable {

  error InvalidState();
  error InvalidPoolID();

  address internal immutable router;
  /**
   * @notice The PoolRegistryAdmin can change the treasury fee up to the MAX_TREASURY_FEE
   * @dev treasury fee is denominated by 1e18, in other words, 1e17 is 10% fee
   */
  uint256 public constant MAX_TREASURY_FEE = 1e17;

  uint256 public treasuryFeeRate;

  address[] public allPools;

  /// @notice `_poolIDs` maps agentID to the pools they have actively borrowed from
  mapping(uint256 => uint256[]) private _poolIDs;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  // ensures that only the pool can change its own state in the agent police
  modifier onlyPool(uint256 poolID) {
    if (poolID > allPools.length) {
      revert InvalidPoolID();
    }

    if (msg.sender != allPools[poolID]) {
      revert Unauthorized();
    }
    _;
  }

  constructor(
    uint256 _treasuryFeeRate,
    address _owner,
    address _router
  ) Ownable(_owner) {
    treasuryFeeRate = _treasuryFeeRate;
    router = _router;
  }

  /*//////////////////////////////////////////////
                      GETTERS
  //////////////////////////////////////////////*/

  /**
   * @notice allPoolsLength returns the number of registered pools
   */
  function allPoolsLength() external view returns (uint256) {
    return allPools.length;
  }

  /**
   * @notice `poolIDs` returns the poolIDs of the pools that the agent has borrowed from
   * @param agentID the agentID of the agent
   */
  function poolIDs(uint256 agentID) external view returns (uint256[] memory) {
    return _poolIDs[agentID];
  }

  /*//////////////////////////////////////////////
                  POOL REGISTERING
  //////////////////////////////////////////////*/

  /**
   * @notice Creates a new pool
   * @param pool The new pool instance
   * @dev only the Pool Factory owner can upgrade pools
   */
  function attachPool(
    IPool pool
  ) external onlyOwner {
    // add the pool to the list of all pools
    allPools.push(address(pool));
  }

  /**
   * @notice upgrades a Pool Accounting instance
   * @param newPool The address of the pool to upgrade
   *
   * @dev only the Pool Factory owner can upgrade pools
   */
  function upgradePool(
    IPool newPool
  ) external onlyOwner {
    uint256 poolID = newPool.id();
    IPool oldPool = IPool(allPools[poolID]);

    // the pool must be shutting down (deposits disabled) to upgrade
    if (!oldPool.isShuttingDown()) revert InvalidState();

    // Update the pool to exist before we decomission the old pool so transfer checks will succeed
    allPools[poolID] = address(newPool);

    uint256 borrowedAmount = oldPool.decommissionPool(newPool);
    // update the accounting in the new pool
    newPool.jumpStartTotalBorrowed(borrowedAmount);
  }

  /**
   * @notice `addPoolToList` adds a pool to an agent's list of pools its borrowed from
   * @param pool the id of the pool to add
   * @dev only an agent can add a pool to its list
   * The agent itself ensures the pool is not a duplicate before calling this function
   */
  function addPoolToList(uint256 agentID, uint256 pool) external onlyPool(pool) {
    _poolIDs[agentID].push(pool);
  }

  /**
   * @notice `removePoolFromList` removes a pool from an agent's list of pools its borrowed from
   * @param pool the id of the pool to add
   * @dev only an agent can add a pool to its list
   */
  function removePoolFromList(uint256 agentID, uint256 pool) external onlyPool(pool) {
    uint256[] storage pools = _poolIDs[agentID];
    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == pool) {
        pools[i] = pools[pools.length - 1];
        pools.pop();
        break;
      }
    }
  }

  /**
   * @dev Sets the treasury fee rate
   */
  function setTreasuryFeeRate(uint256 newFeeRate) external onlyOwner {
    require(newFeeRate <= MAX_TREASURY_FEE, "Pool: Fee too high");
    treasuryFeeRate = newFeeRate;
  }
  
  function createKey(string memory partitionKey, address entity) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, entity));
  }
}
