// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "src/Router/Router.sol";
import "src/Constants/Routes.sol";
import "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {Deployer} from "deploy/Deployer.sol";
import {BaseTest} from "./BaseTest.sol";

struct ContractRoutes {
    address treasury;
    address wFIL;
    address minerRegistry;
    address agentFactory;
    address vcIssuer;
    address agentPolice;
    address credParser;
    address agentDeployer;
}

contract RouterTest is BaseTest {
    error Unauthorized();

    Router routerInstance;
    address routerAdmin;
    ContractRoutes public contractRoutes;

    function setUp() public {
        routerAdmin = makeAddr("ROUTER_ADMIN");

        routerInstance = new Router(routerAdmin);

        vm.startPrank(routerAdmin);
        (, address[] memory contractRouteAddrs) = Deployer.setupContractRoutes(
            address(routerInstance),
            makeAddr("TREASURY"),
            makeAddr("WFIL"),
            makeAddr("MINER_REGISTRY"),
            makeAddr("AGENT_FACTORY"),
            makeAddr("AGENT_POLICE"),
            makeAddr("VC_ISSUER"),
            makeAddr("CRED_PARSER"),
            makeAddr("AGENT_DEPLOYER")
        );
        vm.stopPrank();

        // for ease of testing routes
        contractRoutes = ContractRoutes(
            contractRouteAddrs[0],
            contractRouteAddrs[1],
            contractRouteAddrs[2],
            contractRouteAddrs[3],
            contractRouteAddrs[4],
            contractRouteAddrs[5],
            contractRouteAddrs[6],
            contractRouteAddrs[7]
        );
    }

    function testGetAgentFactory() public {
        assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), contractRoutes.agentFactory);
    }

    function testGetMinerRegistry() public {
        assertEq(routerInstance.getRoute(ROUTE_MINER_REGISTRY), contractRoutes.minerRegistry);
    }

    function testGetRouterOwner() public {
        assertEq(routerInstance.owner(), address(routerAdmin));
    }

    function testGetVCIssuer() public {
        assertEq(routerInstance.getRoute(ROUTE_VC_ISSUER), contractRoutes.vcIssuer);
    }

    function testGetTreasury() public {
        assertEq(routerInstance.getRoute(ROUTE_TREASURY), contractRoutes.treasury);
    }

    function testPushRoute() public {
        address newRoute = makeAddr("NEW_ROUTE");
        vm.prank(routerAdmin);
        routerInstance.pushRoute(ROUTE_AGENT_FACTORY, newRoute);
        assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), newRoute);
    }

    function testPushRouteString() public {
        address newRoute = makeAddr("TEST_ROUTE");
        vm.prank(routerAdmin);
        routerInstance.pushRoute("TEST_ROUTE", newRoute);
        assertEq(routerInstance.getRoute("TEST_ROUTE"), newRoute);
    }

    function testPushRoutes() public {
        address[] memory routes = new address[](2);
        address newRoute = makeAddr("NEW_ROUTE");
        address newRoute2 = makeAddr("NEW_ROUTE2");

        routes[0] = newRoute;
        routes[1] = newRoute2;

        bytes4[] memory routeIDs = new bytes4[](2);
        routeIDs[0] = ROUTE_AGENT_FACTORY;
        routeIDs[1] = ROUTE_INFINITY_POOL;

        vm.prank(routerAdmin);
        routerInstance.pushRoutes(routeIDs, routes);
        assertEq(routerInstance.getRoute(ROUTE_AGENT_FACTORY), newRoute);
        assertEq(routerInstance.getRoute(ROUTE_INFINITY_POOL), newRoute2);
    }

    function testSetAccountNoAuth() public {
        IPool pool = createPool();
        uint256 poolId = pool.id();
        vm.prank(address(pool));
        Router(router).setAccount(0, poolId, Account(0, 0, 0, false));
        address badPool = makeAddr("BAD_POOL");
        vm.prank(badPool);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        Router(router).setAccount(0, poolId, Account(0, 0, 0, false));
    }
}
