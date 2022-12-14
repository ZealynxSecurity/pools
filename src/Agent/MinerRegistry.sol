// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

contract MinerRegistry {

  //TODO: Add Access control! ROLES
  mapping(address => bool) public minerRegistered;

  function addMiners(address[] calldata miners) external {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMiner(miners[i]);
    }
  }

  function removeMiners(address[] calldata miners) external {
    for (uint256 i = 0; i < miners.length; i++) {
      _removeMiner(miners[i]);
    }
  }

  function addMiner(address miner) external {
    require(minerRegistered[miner] == false, "Miner already registered");
    minerRegistered[miner] = true;
  }

  function removeMiner(address miner) external {
    require(minerRegistered[miner] == true, "Miner not registered");
    minerRegistered[miner] = false;
  }

  function _addMiner(address miner) internal {
    require(minerRegistered[miner] == false, "Miner already registered");
    minerRegistered[miner] = true;
  }

  function _removeMiner(address miner) internal {
    require(minerRegistered[miner] == true, "Miner not registered");
    minerRegistered[miner] = false;
  }
}
