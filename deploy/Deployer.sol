// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Router} from "src/Router/Router.sol";
import {Authority} from "src/Auth/Auth.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {IRouter, IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import "src/Constants/Routes.sol";

library Deployer {
  function init() internal returns (
    address router, IMultiRolesAuthority coreAuthority
  ) {
    coreAuthority = IMultiRolesAuthority(address(
      RoleAuthority.newMultiRolesAuthority(address(this),
      Authority(address(0)))
    ));
    router = address(new Router(address(coreAuthority)));
  }

  function initRoles(address router, address systemAdmin) internal {
    RoleAuthority.initFactoryRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY_ADMIN),
      IRouter(router).getRoute(ROUTE_POOL_FACTORY),
      IRouter(router).getRoute(ROUTE_POOL_FACTORY_ADMIN)
    );

    RoleAuthority.initPowerTokenRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_POWER_TOKEN),
      IRouter(router).getRoute(ROUTE_POWER_TOKEN_ADMIN),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY)
    );

    RoleAuthority.initRouterRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_ROUTER_ADMIN)
    );

    RoleAuthority.initMinerRegistryRoles(
      address(router),
      IRouter(router).getRoute(ROUTE_MINER_REGISTRY),
      IRouter(router).getRoute(ROUTE_MINER_REGISTRY_ADMIN),
      IRouter(router).getRoute(ROUTE_AGENT_FACTORY)
    );

    RoleAuthority.transferCoreAuthorityOwnership(address(router), systemAdmin);
  }

  function setupAdminRoutes(
    address router,
    address routerAdmin,
    address agentFactoryAdmin,
    address powerTokenAdmin,
    address minerRegistryAdmin,
    address poolFactoryAdmin,
    address coreAuthAdmin,
    address treasuryAdmin
  ) internal returns (
    bytes4[] memory routeIDs, address[] memory routeAddrs
  ) {
    routeIDs = new bytes4[](7);
    routeAddrs = new address[](7);
    // Add router admin route
    routeIDs[0] = ROUTE_ROUTER_ADMIN;
    routeAddrs[0] = routerAdmin;
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

    IRouter(router).pushRoutes(routeIDs, routeAddrs);
  }

  function setupContractRoutes(
    address router,
    address treasury,
    address wFIL,
    address minerRegistry,
    address agentFactory,
    address poolFactory,
    address stats,
    address powerToken,
    address vcIssuer
  ) internal returns (
    bytes4[] memory routeIDs, address[] memory routeAddrs
  ) {
    routeIDs = new bytes4[](8);
    routeAddrs = new address[](8);
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

    IRouter(router).pushRoutes(routeIDs, routeAddrs);
  }

  function setRouterOnContracts(address router) internal {
    IRouterAware(IRouter(router).getRoute(ROUTE_AGENT_FACTORY)).setRouter(router);
    IRouterAware(IRouter(router).getRoute(ROUTE_MINER_REGISTRY)).setRouter(router);
    IRouterAware(IRouter(router).getRoute(ROUTE_POOL_FACTORY)).setRouter(router);
    IRouterAware(IRouter(router).getRoute(ROUTE_STATS)).setRouter(router);
    IRouterAware(IRouter(router).getRoute(ROUTE_POWER_TOKEN)).setRouter(router);
  }
}
