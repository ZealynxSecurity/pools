// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import "src/Router/Router.sol";
// import "src/Constants/Routes.sol";
// import "src/Types/Interfaces/IRouter.sol";
// import {Account} from "src/Types/Structs/Account.sol";
// import {IPool} from "src/Types/Interfaces/IPool.sol";
// import {Deployer} from "deploy/Deployer.sol";
// import {BaseTest} from "./BaseTest.sol";

// struct ContractRoutes {
//   address treasury;
//   address wFIL;
//   address minerRegistry;
//   address poolRegistryy;
//   address poolFactory;
//   address powerToken;
//   address vcIssuer;
//   address credParser;
//   address accountingDeployer;
// }

// contract RouterTest is BaseTest {
//   error Unauthorized();
//   Router routerInstance;
//   address routerAdmin;
//   ContractRoutes public contractRoutes;

//   function setUp() public {
//     routerAdmin = makeAddr("ROUTER_ADMIN");

//     routerInstance = new Router(routerAdmin);

//     vm.startPrank(routerAdmin);
//     (, address[] memory contractRouteAddrs) = Deployer.setupContractRoutes(
//       address(routerInstance),
//       makeAddr("TREASURY"),
//       makeAddr("WFIL"),
//       makeAddr("MINER_REGISTRY"),
//       makeAddr("AGENT_FACTORY"),
//       makeAddr("AGENT_POLICE"),
//       makeAddr("POOL_FACTORY"),
//       makeAddr("POWER_TOKEN"),
//       makeAddr("VC_ISSUER"),
//       makeAddr("CRED_PARSER"),
//       makeAddr("ACCOUNT_DEPLOYER")
//     );
//     vm.stopPrank();

//     // for ease of testing routes
//     contractRoutes = ContractRoutes(
//       contractRouteAddrs[0],
//       contractRouteAddrs[1],
//       contractRouteAddrs[2],
//       contractRouteAddrs[3],
//       contractRouteAddrs[4],
//       contractRouteAddrs[5],
//       contractRouteAddrs[6],
//       contractRouteAddrs[8],
//       contractRouteAddrs[9]
//     );
//   }

//   function testGetAgentFactory() public {
//     assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), contractRoutes.agentFactory);
//   }

//   function testGetPoolRegistry() public {
//     assertEq(routerInstance.getRoute(ROUTE_POOL_FACTORY), contractRoutes.poolRegistry);
//   }

//   function testGetMinerRegistry() public {
//     assertEq(routerInstance.getRoute(ROUTE_MINER_REGISTRY), contractRoutes.minerRegistry);
//   }

//   function testGetPowerToken() public {
//     assertEq(routerInstance.getRoute(ROUTE_POWER_TOKEN), contractRoutes.powerToken);
//   }

//   function testGetRouterOwner() public {
//     assertEq(routerInstance.owner(), address(routerAdmin));
//   }

//   function testGetVCIssuer() public {
//     assertEq(routerInstance.getRoute(ROUTE_VC_ISSUER), contractRoutes.vcIssuer);
//   }

//   function testGetTreasury() public {
//     assertEq(routerInstance.getRoute(ROUTE_TREASURY), contractRoutes.treasury);
//   }

//   function testGetAccountingDeployer() public {
//     assertEq(routerInstance.getRoute(ROUTE_ACCOUNTING_DEPLOYER), contractRoutes.accountingDeployer);
//   }

//   function testPushRoute() public {
//     address newRoute = makeAddr("NEW_ROUTE");
//     vm.prank(routerAdmin);
//     routerInstance.pushRoute(ROUTE_AGENT_FACTORY, newRoute);
//     assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), newRoute);
//   }

//   function testPushRouteString() public {
//     address newRoute = makeAddr("TEST_ROUTE");
//     vm.prank(routerAdmin);
//     routerInstance.pushRoute("TEST_ROUTE", newRoute);
//     assertEq(routerInstance.getRoute("TEST_ROUTE"), newRoute);
//   }

//   function testPushRoutes() public {
//     address[] memory routes = new address[](2);
//     address newRoute = makeAddr("NEW_ROUTE");
//     address newRoute2 = makeAddr("NEW_ROUTE2");

//     routes[0] = newRoute;
//     routes[1] = newRoute2;

//     bytes4[] memory routeIDs = new bytes4[](2);
//     routeIDs[0] = ROUTE_AGENT_FACTORY;
//     routeIDs[1] = ROUTE_POOL_FACTORY;

//     vm.prank(routerAdmin);
//     routerInstance.pushRoutes(routeIDs, routes);
//     assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), newRoute);
//     assertEq(routerInstance.getRoute(ROUTE_POOL_FACTORY), newRoute2);
//   }

//   function testSetAccountNoAuth() public {
//     address poolOperator = makeAddr("POOL_OPERATOR");
//     string memory poolName = "Test Pool";
//     string memory poolSymbol = "TEST";
//     IPool pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     uint256 poolId = pool.id();
//     vm.prank(address(pool));
//     Router(router).setAccount(0, poolId, Account(10, 20, 30, 10, 20, 30));
//     IPool badPool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     vm.prank(address(badPool));
//     vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
//     Router(router).setAccount(0, poolId, Account(10, 20, 30, 10, 20, 30));
//   }
// }
