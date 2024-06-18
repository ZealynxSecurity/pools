// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {PoolToken} from "shim/PoolToken.sol";
import {Router} from "src/Router/Router.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import "src/Constants/Routes.sol";

library Deployer {
    function setupContractRoutes(
        address router,
        address treasury,
        address wFIL,
        address minerRegistry,
        address agentFactory,
        address agentPolice,
        address vcIssuer,
        address credParser,
        address agentDeployer
    ) internal returns (bytes4[] memory routeIDs, address[] memory routeAddrs) {
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
        // Add vc issuer route
        routeIDs[4] = ROUTE_VC_ISSUER;
        routeAddrs[4] = vcIssuer;
        // Add agent police route
        routeIDs[5] = ROUTE_AGENT_POLICE;
        routeAddrs[5] = agentPolice;
        // Add cred parser
        routeIDs[6] = ROUTE_CRED_PARSER;
        routeAddrs[6] = credParser;
        // Add agent deployer
        routeIDs[7] = ROUTE_AGENT_DEPLOYER;
        routeAddrs[7] = agentDeployer;

        IRouter(router).pushRoutes(routeIDs, routeAddrs);
    }
}
