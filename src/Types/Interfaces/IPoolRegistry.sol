// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolRegistry {
  function treasuryFeeRate() external view returns (uint256);
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function poolIDs(uint256 agentID) external view returns (uint256[] memory);
  function addPoolToList(uint256 agentID, uint256 pool) external;
  function removePoolFromList(uint256 agentID, uint256 pool) external;
  function attachPool(IPool pool) external;
  function upgradePool(IPool pool) external;
  function setTreasuryFeeRate(uint256 fee) external;
}
