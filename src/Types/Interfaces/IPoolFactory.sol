// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolFactory {
  function treasuryFeeRate() external view returns (uint256);
  function feeThreshold() external view returns (uint256);
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function isPool(address pool) external view returns (bool);
  function attachPool(IPool pool) external;
  function upgradePool(IPool pool) external;
  function setTreasuryFeeRate(uint256 fee) external;
  function setFeeThreshold(uint256 threshold) external;
}
