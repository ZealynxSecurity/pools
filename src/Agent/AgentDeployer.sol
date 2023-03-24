// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Agent} from "src/Agent/Agent.sol";

/// @dev this is to reduce contract size in AgentFactory
contract AgentDeployer {
  function deploy(
    address router,
    uint256 agentId,
    address owner,
    address operator
  ) external returns (Agent agent) {
    agent = new Agent(router, agentId, owner, operator);
  }
}
