// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {RouterAware} from "src/Router/RouterAware.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";

contract MinerRegistry is RouterAware {
  mapping(address => bool) public minerRegistered;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier requiresAuth() virtual {
    require(RoleAuthority.canCallSubAuthority(router, address(this)), "MinerRegistry: Not authorized");
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    REGISTRY STATE MUTATING FUNCS
  //////////////////////////////////////////////////////////////*/

  function addMiners(address[] calldata miners) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMiner(miners[i]);
    }
  }

  function removeMiners(address[] calldata miners) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      _removeMiner(miners[i]);
    }
  }

  function addMiner(address miner) external requiresAuth {
    require(minerRegistered[miner] == false, "Miner already registered");
    minerRegistered[miner] = true;
  }

  function removeMiner(address miner) external requiresAuth {
    require(minerRegistered[miner] == true, "Miner not registered");
    minerRegistered[miner] = false;
  }

  /*///////////////////////////////////////////////////////////////
                          INTERNAL FUNCS
  //////////////////////////////////////////////////////////////*/

  function _addMiner(address miner) internal {
    require(minerRegistered[miner] == false, "Miner already registered");
    minerRegistered[miner] = true;
  }

  function _removeMiner(address miner) internal {
    require(minerRegistered[miner] == true, "Miner not registered");
    minerRegistered[miner] = false;
  }
}
