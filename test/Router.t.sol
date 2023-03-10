// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Router/Router.sol";
import "src/Constants/Routes.sol";
import "src/Types/Interfaces/IRouter.sol";
import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {Authority} from "src/Auth/Auth.sol";
import {Deployer} from "deploy/Deployer.sol";

// for ease of testing routes
struct AdminRoutes {
  address routerAdmin;
  address agentFactoryAdmin;
  address powerTokenAdmin;
  address minerRegistryAdmin;
  address poolFactoryAdmin;
  address coreAuthorityAdmin;
  address treasuryAdmin;
}

struct ContractRoutes {
  address treasury;
  address wFIL;
  address minerRegistry;
  address agentFactory;
  address poolFactory;
  address powerToken;
  address vcIssuer;
  address coreAuthority;
  address credParser;
  address accountingDeployer;
}

contract RouterTest is Test {
  Router router;
  address routerAdmin;
  ContractRoutes public contractRoutes;
  AdminRoutes public adminRoutes;

  MultiRolesAuthority authority;
  function setUp() public {
    routerAdmin = makeAddr("ROUTER_ADMIN");
    authority = AuthController.newMultiRolesAuthority(address(this), Authority(address(0)));

    router = new Router(address(authority));

    (, address[] memory adminRouteAddrs) = Deployer.setupAdminRoutes(
      address(router),
      routerAdmin,
      makeAddr("AGENT_FACTORY_ADMIN"),
      makeAddr("POWER_TOKEN_ADMIN"),
      makeAddr("MINER_REGISTRY_ADMIN"),
      makeAddr("POOL_FACTORY_ADMIN"),
      makeAddr("CORE_AUTHORITY_ADMIN"),
      makeAddr("TREASURY_ADMIN"),
      makeAddr("AGENT_POLICE_ADMIN")
    );
    (, address[] memory contractRouteAddrs) = Deployer.setupContractRoutes(
      address(router),
      makeAddr("TREASURY"),
      makeAddr("WFIL"),
      makeAddr("MINER_REGISTRY"),
      makeAddr("AGENT_FACTORY"),
      makeAddr("AGENT_POLICE"),
      makeAddr("POOL_FACTORY"),
      makeAddr("POWER_TOKEN"),
      makeAddr("VC_ISSUER"),
      makeAddr("CRED_PARSER"),
      makeAddr("ACCOUNT_DEPLOYER")
    );

    // for ease of testing routes
    adminRoutes = AdminRoutes(
      adminRouteAddrs[0],
      adminRouteAddrs[1],
      adminRouteAddrs[2],
      adminRouteAddrs[3],
      adminRouteAddrs[4],
      adminRouteAddrs[5],
      adminRouteAddrs[6]
    );
    contractRoutes = ContractRoutes(
      contractRouteAddrs[0],
      contractRouteAddrs[1],
      contractRouteAddrs[2],
      contractRouteAddrs[3],
      contractRouteAddrs[4],
      contractRouteAddrs[5],
      contractRouteAddrs[6],
      address(authority),
      contractRouteAddrs[8],
      contractRouteAddrs[9]
    );

    AuthController.transferCoreAuthorityOwnership(address(router), routerAdmin);
  }

  function testGetAgentFactory() public {
    assertEq(router.getRoute(ROUTE_AGENT_FACTORY), contractRoutes.agentFactory);
  }

  function testGetPoolFactory() public {
    assertEq(router.getRoute(ROUTE_POOL_FACTORY), contractRoutes.poolFactory);
  }

  function testGetMinerRegistry() public {
    assertEq(router.getRoute(ROUTE_MINER_REGISTRY), contractRoutes.minerRegistry);
  }

  function testGetAuthority() public {
    assertEq(router.getRoute(ROUTE_CORE_AUTHORITY), address(authority));
  }

  function testGetPowerToken() public {
    assertEq(router.getRoute(ROUTE_POWER_TOKEN), contractRoutes.powerToken);
  }

  function testGetRouterAdmin() public {
    assertEq(router.getRoute(ROUTE_SYSTEM_ADMIN), address(routerAdmin));
  }

  function testGetPowerTokenAdmin() public {
    assertEq(router.getRoute(ROUTE_POWER_TOKEN_ADMIN), adminRoutes.powerTokenAdmin);
  }

    function testGetMinerRegistryAdmin() public {
    assertEq(router.getRoute(ROUTE_MINER_REGISTRY_ADMIN), adminRoutes.minerRegistryAdmin);
  }

    function testGetPoolFactoryAdmin() public {
    assertEq(router.getRoute(ROUTE_POOL_FACTORY_ADMIN), adminRoutes.poolFactoryAdmin);
  }

    function testGetSystemAdmin() public {
    assertEq(router.getRoute(ROUTE_CORE_AUTH_ADMIN), adminRoutes.coreAuthorityAdmin);
  }

  function testGetVCIssuer() public {
    assertEq(router.getRoute(ROUTE_VC_ISSUER), contractRoutes.vcIssuer);
  }

  function testGetTreasury() public {
    assertEq(router.getRoute(ROUTE_TREASURY), contractRoutes.treasury);
  }

  function testGetAccountingDeployer() public {
    assertEq(router.getRoute(ROUTE_ACCOUNTING_DEPLOYER), contractRoutes.accountingDeployer);
  }


  function testGetTreasuryAdmin() public {
    assertEq(router.getRoute(ROUTE_TREASURY_ADMIN), adminRoutes.treasuryAdmin);
  }


  function testPushRoute() public {
    address newRoute = makeAddr("NEW_ROUTE");
    vm.prank(routerAdmin);
    router.pushRoute(ROUTE_AGENT_FACTORY, newRoute);
    assertEq(router.getRoute(ROUTE_AGENT_FACTORY), newRoute);
  }

  function testPushRouteString() public {
    address newRoute = makeAddr("TEST_ROUTE");
    vm.prank(routerAdmin);
    router.pushRoute("TEST_ROUTE", newRoute);
    assertEq(router.getRoute("TEST_ROUTE"), newRoute);
  }

  function testPushRoutes() public {
    address[] memory routes = new address[](2);
    address newRoute = makeAddr("NEW_ROUTE");
    address newRoute2 = makeAddr("NEW_ROUTE2");

    routes[0] = newRoute;
    routes[1] = newRoute2;

    bytes4[] memory routeIDs = new bytes4[](2);
    routeIDs[0] = ROUTE_AGENT_FACTORY;
    routeIDs[1] = ROUTE_POOL_FACTORY;

    vm.prank(routerAdmin);
    router.pushRoutes(routeIDs, routes);
    assertEq(router.getRoute(ROUTE_AGENT_FACTORY), newRoute);
    assertEq(router.getRoute(ROUTE_POOL_FACTORY), newRoute2);
  }
}
