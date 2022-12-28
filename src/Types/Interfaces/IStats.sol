// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IStats {
  function isDebtor(address agent) external view returns (bool);
  function isDebtor(address agent, uint256 poolID) external view returns (bool);

  function hasPenalties(address agent) external returns (bool);
  function hasPenalties(address agent, uint256 poolID) external returns (bool);
}
