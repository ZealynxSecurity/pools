// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AuthController} from "src/Auth/AuthController.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_AGENT_FACTORY} from "src/Constants/Routes.sol";

contract MinerRegistry is IMinerRegistry {

  address public router;

  error InvalidParams();

  // maps keccak256(agentID, minerAddr) => registered status
  mapping(bytes32 => bool) private _minerRegistered;

  constructor(address _router) {
    router = _router;
  }

  /*///////////////////////////////////////////////////////////////
                            GETTERS
  //////////////////////////////////////////////////////////////*/

  function minerRegistered(uint256 agentID, uint64 miner) external view returns (bool) {
    return _minerRegistered[_createMapKey(agentID, miner)];
  }

  /*///////////////////////////////////////////////////////////////
                            MODIFIERS
  //////////////////////////////////////////////////////////////*/

  modifier onlyAgent {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    REGISTRY STATE MUTATING FUNCS
  //////////////////////////////////////////////////////////////*/

  function addMiner(uint64 miner) external onlyAgent {
    bytes32 key = _createMapKey(_getIDFromAgent(msg.sender), miner);

    if (_minerRegistered[key]) revert InvalidParams();

    _minerRegistered[key] = true;

    emit AddMiner(msg.sender, miner);
  }

  function removeMiner(uint64 miner) external onlyAgent {
    bytes32 key = _createMapKey(_getIDFromAgent(msg.sender), miner);

    if (!_minerRegistered[key]) revert InvalidParams();

    _minerRegistered[key] = false;

    emit RemoveMiner(msg.sender, miner);
  }

  /*///////////////////////////////////////////////////////////////
                          INTERNAL FUNCS
  //////////////////////////////////////////////////////////////*/

  function _getIDFromAgent(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _createMapKey(uint256 agent, uint64 miner) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(agent, miner));
  }
}
