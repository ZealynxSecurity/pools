// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Agent} from "src/Agent/Agent.sol";

/// @dev this is to reduce contract size in AgentFactory
library AgentDeployer {
  function deploy(address router, uint256 agentId) external returns (Agent agent) {
    agent = new Agent(router, agentId);
  }
}
