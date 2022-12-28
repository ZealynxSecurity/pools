// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AuthController} from "src/Auth/AuthController.sol";
import {Agent} from "src/Agent/Agent.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {
  ROUTE_POWER_TOKEN,
  ROUTE_VC_ISSUER,
  ROUTE_MINER_REGISTRY
} from "src/Constants/Routes.sol";

contract AgentFactory is IAgentFactory, RouterAware {
  mapping(address => uint256) public agents;
  // we start at ID 1 because ID 0 is reserved for empty agent ID
  uint256 public agentCount = 0;

  function create(address operator) external returns (address) {
    agentCount++;
    Agent agent = new Agent(router, agentCount);
    agents[address(agent)] = agentCount;

    if (operator != address(0)) {
      operator = msg.sender;
    }

    AuthController.initAgentRoles(
      router,
      address(agent),
      operator
    );

    emit CreateAgent(agent.id(), address(agent), operator);

    return address(agent);
  }

  function isAgent(address agent) external view returns (bool) {
    return agents[agent] > 0;
  }
}
