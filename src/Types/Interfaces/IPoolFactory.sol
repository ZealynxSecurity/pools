// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolFactory {
  function treasuryFeeRate() external view returns (uint256);
  function feeThreshold() external view returns (uint256);
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function isPool(address pool) external view returns (bool);
  function isPoolImplementation(address poolImplementation) external view returns (bool);
  function createPool(
    string calldata name,
    string calldata symbol,
    address owner,
    address operator
  ) external returns (IPool pool);
  function upgradePool(uint256 poolId) external returns (IPool newPool);
  function approveImplementation(address implementation) external;
  function revokeImplementation(address implementation) external;
  function setTreasuryFeeRate(uint256 fee) external;
  function setFeeThreshold(uint256 threshold) external;
}
