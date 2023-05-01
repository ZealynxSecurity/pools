// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Agent} from "src/Agent/Agent.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentDeployer} from "src/Types/Interfaces/IAgentDeployer.sol";

/// @dev this is to reduce contract size in AgentFactory
contract AgentDeployer is IAgentDeployer {
  uint8 public immutable version = 1;

  function deploy(
    address router,
    uint256 agentId,
    address owner,
    address operator
  ) external returns (address agent) {
    agent = address(new Agent(version, agentId, router, owner, operator));
  }
}
