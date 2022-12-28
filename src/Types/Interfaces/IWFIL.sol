// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IWFIL {
  function deposit() external payable;
  function withdraw(uint256 _amount) external payable;
}
