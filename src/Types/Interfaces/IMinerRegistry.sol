// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IMinerRegistry {
  event AddMiner(address indexed agent, uint64 indexed miner);
  event RemoveMiner(address indexed agent, uint64 indexed miner);

  function addMiners (uint64[] calldata miners) external;
  function removeMiners (uint64[] calldata miners) external;
  function addMiner(uint64 miner) external;
  function removeMiner(uint64 miner) external;
  function minerRegistered(uint256 agentID, uint64 miner) external view returns (bool);
}
