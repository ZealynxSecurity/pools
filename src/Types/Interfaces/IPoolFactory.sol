// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolFactory {
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function isPool(address pool) external view returns (bool);
  function isPoolTemplate(address pool) external view returns (bool);
  function createPool(
    string calldata name,
    string calldata symbol,
    address operator,
    address broker,
    address template
  ) external returns (IPool pool);
  function approveBroker(address broker) external;
  function revokeBroker(address broker) external;
  function approveTemplate(address template) external;
  function revokeTemplate(address template) external;

}
