// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IPreStake {
  function totalValueLocked() external view returns (uint256);
}
