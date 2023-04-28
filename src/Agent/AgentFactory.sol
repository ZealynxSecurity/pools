// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AuthController} from "src/Auth/AuthController.sol";
import {Agent} from "src/Agent/Agent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
import {
  ROUTE_VC_ISSUER,
  ROUTE_MINER_REGISTRY
} from "src/Constants/Routes.sol";

contract AgentFactory is IAgentFactory {

  error Unauthorized();

  mapping(address => uint256) public agents;
  // we start at ID 1 because ID 0 is reserved for empty agent ID
  uint256 public agentCount = 0;

  address public immutable router;

  constructor(address _router) {
    router = _router;
  }

  function create(address owner, address operator) external returns (address agent) {
    agentCount++;
    agent = GetRoute.agentDeployer(router).deploy(
      router,
      agentCount,
      owner,
      operator
    );
    agents[agent] = agentCount;

    emit CreateAgent(agentCount, agent, msg.sender);

    return agent;
  }

  /**
   * @notice upgrades an Agent instance
   * @param agent The old agent's address to upgrade
   * @return newAgent The new agent's address
   */
  function upgradeAgent(
    address agent
  ) external returns (address newAgent) {
    IAgent oldAgent = IAgent(agent);
    address owner = IAuth(address(oldAgent)).owner();
    uint256 agentId = agents[agent];
    // only the Agent's owner can upgrade, and only a registered agent can be upgraded
    if (owner != msg.sender || agentId == 0) revert Unauthorized();
    // deploy a new instance of Agent with the same ID and auth
    newAgent = GetRoute.agentDeployer(router).deploy(
      router,
      agentId,
      owner,
      IAuth(address(oldAgent)).operator()
    );
    // Register the new agent and unregister the old agent
    agents[newAgent] = agentId;
    // transfer funds from old agent to new agent and mark old agent as decommissioning
    oldAgent.decommissionAgent(newAgent);
    // delete the old agent from the registry
    agents[agent] = 0;
  }

  function isAgent(address agent) external view returns (bool) {
    return agents[agent] > 0;
  }
}
