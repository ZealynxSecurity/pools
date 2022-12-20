// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IAgentFactory {
  function create(address miner) external returns (address);
  function revokeOwnership(address agent) external;
  function agents(address agent) external view returns (bool);
  function activeMiners(address miner) external view returns (address);
  function setVerifierName(string memory name, string memory version) external;
  function verifierName() external returns (string memory);
  function verifierVersion() external returns (string memory);
}
