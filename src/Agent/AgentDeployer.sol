// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Agent} from "src/Agent/Agent.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentDeployer} from "src/Types/Interfaces/IAgentDeployer.sol";

/// @dev this is to reduce contract size in AgentFactory
contract AgentDeployer is IAgentDeployer {
  uint8 public constant version = 1;

  function deploy(
    address router,
    uint256 agentId,
    address owner,
    address operator,
    address adoRequestKey
  ) external returns (address agent) {
    agent = address(new Agent(agentId, router, owner, operator, adoRequestKey));
  }
}
