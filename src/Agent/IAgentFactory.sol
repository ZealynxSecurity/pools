// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IAgentFactory {
  function create(address _miner) external returns (address);
  function revokeOwnership(address _agent) external;
  function agents(address agent) external view returns (bool);
  function activeMiners(address miner) external view returns (address);
}
