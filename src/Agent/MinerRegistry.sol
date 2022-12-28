// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Auth} from "src/Auth/Auth.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {ROUTE_AGENT_FACTORY} from "src/Constants/Routes.sol";

contract MinerRegistry is IMinerRegistry, RouterAware {
  // maps agent ID => miner => registered status
  mapping(uint256 => mapping(address => bool)) public minerRegistered;

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier requiresAuth {
    AuthController.requiresSubAuth(router, address(this));
    _;
  }

  modifier onlyAgent {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    REGISTRY STATE MUTATING FUNCS
  //////////////////////////////////////////////////////////////*/

  function addMiners(address[] calldata miners) external onlyAgent {
    for (uint256 i = 0; i < miners.length; ++i) {
      _addMiner(miners[i]);
    }
  }

  function removeMiners(address[] calldata miners) external onlyAgent {
    for (uint256 i = 0; i < miners.length; ++i) {
      _removeMiner(miners[i]);
    }
  }

  function addMiner(address miner) external onlyAgent {
    _addMiner(miner);
  }

  function removeMiner(address miner) external onlyAgent {
    _removeMiner(miner);
  }

  /*///////////////////////////////////////////////////////////////
                          INTERNAL FUNCS
  //////////////////////////////////////////////////////////////*/

  function _getIDFromAgent(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _addMiner(address miner) internal {
    uint256 id = _getIDFromAgent(msg.sender);
    require(minerRegistered[id][miner] == false, "Miner already registered");
    minerRegistered[id][miner] = true;

    emit AddMiner(msg.sender, miner);
  }

  function _removeMiner(address miner) internal {
    uint256 id = _getIDFromAgent(msg.sender);
    require(minerRegistered[id][miner], "Miner not registered");
    minerRegistered[id][miner] = false;

    emit RemoveMiner(msg.sender, miner);
  }
}
