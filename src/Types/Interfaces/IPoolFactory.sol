// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolFactory {
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function isPool(address pool) external view returns (bool);
  function createPool(
    string memory _name,
    string memory _symbol,
    address operator,
    address rateModule
  ) external returns (IPool pool);
}
