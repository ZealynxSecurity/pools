// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IMinerRegistry {
  event AddMiner(address indexed agent, address indexed miner);
  event RemoveMiner(address indexed agent, address indexed miner);

  function addMiners (address[] calldata miners) external;
  function removeMiners (address[] calldata miners) external;
  function addMiner(address miner) external;
  function removeMiner(address miner) external;
  function minerRegistered(uint256 agentID, address miner) external view returns (bool);
}
