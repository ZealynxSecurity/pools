pragma solidity ^0.8.15;

interface IMinerRegistry {
  function addMiner(address miner) external;
  function removeMiner(address miner) external;
  function minerRegistered(address miner) external view returns (bool);
}