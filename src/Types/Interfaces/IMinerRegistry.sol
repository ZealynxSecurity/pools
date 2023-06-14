// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface IMinerRegistry {
  event AddMiner(address indexed agent, uint64 indexed miner);
  event RemoveMiner(address indexed agent, uint64 indexed miner);

  function addMiner(uint256 agentId, uint64 miner) external;
  function removeMiner(uint256 agentId, uint64 miner) external;
  function minerRegistered(uint256 agentID, uint64 miner) external view returns (bool);
  function minersCount(uint256 agentID) external view returns (uint256);
  function getMiner(uint256 agentID, uint256 index) external view returns (uint64);
}
