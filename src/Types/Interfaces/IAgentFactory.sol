// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IAgentFactory {
  event CreateAgent(uint256 indexed agentID, address indexed agent, address indexed operator);

  function agents(address agent) external view returns (uint256);
  function agentCount() external view returns (uint256);
  function isAgent(address agent) external view returns (bool);
  function create(address owner, address operator) external returns (address);
  function upgradeAgent(address agent) external returns (address newAgent);
}
