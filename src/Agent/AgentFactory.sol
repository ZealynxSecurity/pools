// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {Agent} from "src/Agent/Agent.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {
  ROUTE_POWER_TOKEN,
  ROUTE_VC_ISSUER,
  ROUTE_MINER_REGISTRY
} from "src/Constants/Routes.sol";

contract AgentFactory is RouterAware {
  mapping(address => bool) public agents;
  string public verifierName;
  string public verifierVersion;

  constructor(string memory _name, string memory _version) {
    verifierName = _name;
    verifierVersion = _version;
  }

  function create(address operator) external returns (address) {
    Agent agent = new Agent(router, verifierName, verifierVersion);
    agents[address(agent)] = true;

    RoleAuthority.initAgentRoles(
      router,
      address(agent),
      operator,
      IRouter(router).getRoute(ROUTE_VC_ISSUER),
      IRouter(router).getRoute(ROUTE_MINER_REGISTRY)
    );

    return address(agent);
  }

  function setVerifierName(string memory _name, string memory _version) external {
    require(RoleAuthority.canCallSubAuthority(router, address(this)), "AgentFactory: Not authorized");
    verifierName = _name;
    verifierVersion = _version;
  }
}
