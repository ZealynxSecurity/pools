// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface Swap {
  // in v0, swap is hardcoded to return some fixed exchange rate
  function swap(address fromToken, address toToken) external returns (uint256);
  function provideLiquidity(address token1, address token2) external;
}
