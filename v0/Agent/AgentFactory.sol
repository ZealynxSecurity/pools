// SPDX-License-Identifier: UNLICENSED
// solhint-disable
pragma solidity 0.8.17;

import {AuthController} from "v0/Auth/AuthController.sol";
import {IRouter} from "v0/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "v0/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "v0/Types/Interfaces/IAgent.sol";
import {IAuth} from "v0/Types/Interfaces/IAuth.sol";
import {IAgentDeployer} from "v0/Types/Interfaces/IAgentDeployer.sol";
import {GetRoute} from "v0/Router/GetRoute.sol";
import {
  ROUTE_VC_ISSUER,
  ROUTE_MINER_REGISTRY
} from "v0/Constants/Routes.sol";

contract AgentFactory is IAgentFactory {

  error Unauthorized();

  mapping(address => uint256) public agents;
  // we start at ID 1 because ID 0 is reserved for empty agent ID
  uint256 public agentCount = 0;

  address internal immutable router;

  constructor(address _router) {
    router = _router;
  }

  function create(address owner, address operator, address adoRequestKey) external returns (address agent) {
    agentCount++;
    agent = GetRoute.agentDeployer(router).deploy(
      router,
      agentCount,
      owner,
      operator,
      adoRequestKey
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
    IAgentDeployer agDeployer = GetRoute.agentDeployer(router);
    IAgent oldAgent = IAgent(agent);

    // can only upgrade to a new version of the agent
    if (agDeployer.version() <= oldAgent.version()) revert Unauthorized();

    address owner = IAuth(address(oldAgent)).owner();
    uint256 agentId = agents[agent];
    // only the Agent's owner can upgrade (unless on administration), and only a registered agent can be upgraded
    if ((owner != msg.sender && oldAgent.administration() != msg.sender) || agentId == 0) revert Unauthorized();
    // deploy a new instance of Agent with the same ID and auth
    newAgent = agDeployer.deploy(
      router,
      agentId,
      owner,
      IAuth(address(oldAgent)).operator(),
      oldAgent.adoRequestKey()
    );
    // Register the new agent and unregister the old agent
    agents[newAgent] = agentId;
    // delete the old agent from the registry
    agents[agent] = 0;
    // transfer funds from old agent to new agent and mark old agent as decommissioning
    oldAgent.decommissionAgent(newAgent);
  }

  function isAgent(address agent) external view returns (bool) {
    return agents[agent] > 0;
  }
}
