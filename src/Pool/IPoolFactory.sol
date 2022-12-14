// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPool4626} from "src/Pool/IPool4626.sol";

interface IPoolFactory {
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function createSimpleInterestPool(string memory name, uint256 baseInterestRate) external returns (IPool4626);
}
