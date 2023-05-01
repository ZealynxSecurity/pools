// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AuthController} from "src/Auth/AuthController.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_AGENT_FACTORY} from "src/Constants/Routes.sol";

contract MinerRegistry is IMinerRegistry {

  address internal immutable router;

  error InvalidParams();

  // maps keccak256(agentID, minerAddr) => registered status
  mapping(bytes32 => bool) private _minerRegistered;

  mapping(uint256 => uint64[]) private _minersByAgent;

  constructor(address _router) {
    router = _router;
  }

  /*///////////////////////////////////////////////////////////////
                            GETTERS
  //////////////////////////////////////////////////////////////*/

  function minerRegistered(uint256 agentID, uint64 miner) external view returns (bool) {
    return _minerRegistered[_createMapKey(agentID, miner)];
  }

  function minersCount(uint256 agentID) external view returns (uint256) {
    return _minersByAgent[agentID].length;
  }

  function getMiner(uint256 agentID, uint256 index) external view returns (uint64) {
    return _minersByAgent[agentID][index];
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

  function addMiner(uint256 agentID, uint64 miner) external onlyAgent {
    bytes32 key = _createMapKey(agentID, miner);

    if (_minerRegistered[key]) revert InvalidParams();
    _minersByAgent[agentID].push(miner);
    _minerRegistered[key] = true;

    emit AddMiner(msg.sender, miner);
  }

  function removeMiner(uint256 agentID, uint64 miner) external onlyAgent {
    bytes32 key = _createMapKey(agentID, miner);

    if (!_minerRegistered[key]) revert InvalidParams();
    _popMinerFromList(miner, _minersByAgent[agentID]);
    _minerRegistered[key] = false;

    emit RemoveMiner(msg.sender, miner);
  }

  /*///////////////////////////////////////////////////////////////
                          INTERNAL FUNCS
  //////////////////////////////////////////////////////////////*/

  function _createMapKey(uint256 agent, uint64 miner) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(agent, miner));
  }

  function _popMinerFromList(uint64 miner, uint64[] storage miners) internal{
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        miners[i] = miners[miners.length - 1];
        miners.pop();
        break;
      }
    }
  }
}
