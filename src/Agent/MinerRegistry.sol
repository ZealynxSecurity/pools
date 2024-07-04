// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {GetRoute} from "src/Router/GetRoute.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";

contract MinerRegistry is IMinerRegistry {

  address internal immutable router;
  IAgentFactory internal agentFactory;

  error Unauthorized();
  error InvalidParams();

  // maps keccak256(agentID, minerAddr) => registered status
  mapping(bytes32 => bool) private _minerRegistered;

  mapping(uint256 => uint64[]) private _minersByAgent;

  constructor(address _router, IAgentFactory _agentFactory) {
    router = _router;

    agentFactory = _agentFactory;
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

  modifier onlyAgent(uint256 agentID) {
    _onlyAgent(agentID);
    _;
  }

  /*///////////////////////////////////////////////////////////////
                    REGISTRY STATE MUTATING FUNCS
  //////////////////////////////////////////////////////////////*/

  function addMiner(uint256 agentID, uint64 miner) external onlyAgent(agentID) {
    bytes32 key = _createMapKey(agentID, miner);

    if (_minerRegistered[key]) revert InvalidParams();
    _minersByAgent[agentID].push(miner);
    _minerRegistered[key] = true;

    emit AddMiner(msg.sender, miner);
  }

  function removeMiner(uint256 agentID, uint64 miner) external onlyAgent(agentID) {
    bytes32 key = _createMapKey(agentID, miner);

    if (!_minerRegistered[key]) revert InvalidParams();
    _popMinerFromList(miner, _minersByAgent[agentID]);
    _minerRegistered[key] = false;

    emit RemoveMiner(msg.sender, miner);
  }

  function refreshRoutes() external {
    agentFactory = GetRoute.agentFactory(router);
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

  function _onlyAgent(uint256 agentID) internal view {
    uint256 _agentID = agentFactory.agents(msg.sender);
    if (_agentID == 0 || _agentID != agentID) revert Unauthorized();
  }
}
