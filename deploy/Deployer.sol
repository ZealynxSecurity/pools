// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Router} from "src/Router/Router.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Authority} from "src/Auth/Auth.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IRouter, IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import "src/Constants/Routes.sol";

library Deployer {
  function init() internal returns (
    address router, IMultiRolesAuthority coreAuthority
  ) {
    coreAuthority = IMultiRolesAuthority(address(
      AuthController.newMultiRolesAuthority(address(this),
      Authority(address(0)))
    ));
    router = address(new Router(address(coreAuthority)));
  }

  function initRoles(address router, address systemAdmin) internal {
    AuthController.initFactoryRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY_ADMIN),
      IRouter(router).getRoute(ROUTE_POOL_FACTORY),
      IRouter(router).getRoute(ROUTE_POOL_FACTORY_ADMIN)
    );

    AuthController.initPowerTokenRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_POWER_TOKEN),
      IRouter(router).getRoute(ROUTE_POWER_TOKEN_ADMIN)
    );

    AuthController.initAgentPoliceRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_AGENT_POLICE),
      IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN)
    );

    AuthController.initMinerRegistryRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_MINER_REGISTRY),
      IRouter(router).getRoute(ROUTE_MINER_REGISTRY_ADMIN)
    );

    AuthController.transferCoreAuthorityOwnership(address(router), systemAdmin);
  }

  function setupAdminRoutes(
    address router,
    address systemAdmin,
    address agentFactoryAdmin,
    address powerTokenAdmin,
    address minerRegistryAdmin,
    address poolFactoryAdmin,
    address coreAuthAdmin,
    address treasuryAdmin,
    address agentPoliceAdmin
  ) internal returns (
    bytes4[] memory routeIDs, address[] memory routeAddrs
  ) {
    routeIDs = new bytes4[](8);
    routeAddrs = new address[](8);
    // Add router admin route
    routeIDs[0] = ROUTE_SYSTEM_ADMIN;
    routeAddrs[0] = systemAdmin;
    // Add agent factory admin route
    routeIDs[1] = ROUTE_AGENT_FACTORY_ADMIN;
    routeAddrs[1] = agentFactoryAdmin;
    // Add power token admin route
    routeIDs[2] = ROUTE_POWER_TOKEN_ADMIN;
    routeAddrs[2] = powerTokenAdmin;
    // Add miner registry admin route
    routeIDs[3] = ROUTE_MINER_REGISTRY_ADMIN;
    routeAddrs[3] = minerRegistryAdmin;
    // Add pool factory admin route
    routeIDs[4] = ROUTE_POOL_FACTORY_ADMIN;
    routeAddrs[4] = poolFactoryAdmin;
    // Add core authority admin route
    routeIDs[5] = ROUTE_CORE_AUTH_ADMIN;
    routeAddrs[5] = coreAuthAdmin;
    // Add treasury admin route
    routeIDs[6] = ROUTE_TREASURY_ADMIN;
    routeAddrs[6] = treasuryAdmin;
    // Add agent police admin route
    routeIDs[7] = ROUTE_AGENT_POLICE_ADMIN;
    routeAddrs[7] = agentPoliceAdmin;

    IRouter(router).pushRoutes(routeIDs, routeAddrs);
  }

  function setupContractRoutes(
    address router,
    address treasury,
    address wFIL,
    address minerRegistry,
    address agentFactory,
    address agentPolice,
    address poolFactory,
    address stats,
    address powerToken,
    address vcIssuer
  ) internal returns (
    bytes4[] memory routeIDs, address[] memory routeAddrs
  ) {
    routeIDs = new bytes4[](9);
    routeAddrs = new address[](9);
    // Add treasury route
    routeIDs[0] = ROUTE_TREASURY;
    routeAddrs[0] = treasury;
    // Add wFIL route
    routeIDs[1] = ROUTE_WFIL_TOKEN;
    routeAddrs[1] = wFIL;
    // Add miner registry route
    routeIDs[2] = ROUTE_MINER_REGISTRY;
    routeAddrs[2] = minerRegistry;
    // Add agent factory route
    routeIDs[3] = ROUTE_AGENT_FACTORY;
    routeAddrs[3] = agentFactory;
    // Add pool factory route
    routeIDs[4] = ROUTE_POOL_FACTORY;
    routeAddrs[4] = poolFactory;
    // Add stats route
    routeIDs[5] = ROUTE_STATS;
    routeAddrs[5] = stats;
    // Add power token route
    routeIDs[6] = ROUTE_POWER_TOKEN;
    routeAddrs[6] = powerToken;
    // Add vc issuer route
    routeIDs[7] = ROUTE_VC_ISSUER;
    routeAddrs[7] = vcIssuer;
    // Add agent police route
    routeIDs[8] = ROUTE_AGENT_POLICE;
    routeAddrs[8] = agentPolice;

    IRouter(router).pushRoutes(routeIDs, routeAddrs);
  }

  function setRouterOnContracts(address router) internal {
    bytes4[6] memory routerAwareRoutes = [
      ROUTE_AGENT_FACTORY,
      ROUTE_MINER_REGISTRY,
      ROUTE_POOL_FACTORY,
      ROUTE_STATS,
      ROUTE_POWER_TOKEN,
      ROUTE_AGENT_POLICE
    ];

    for (uint256 i = 0; i < routerAwareRoutes.length; i++) {
      IRouterAware(IRouter(router).getRoute(routerAwareRoutes[i])).setRouter(router);
    }
  }
}
