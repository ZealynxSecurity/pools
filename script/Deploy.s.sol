// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {WFIL} from "shim/WFIL.sol";
import {Deployer} from "deploy/Deployer.sol";
import {Router} from "src/Router/Router.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {PoolRegistry} from "src/Pool/PoolRegistry.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRouter, IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
import "src/Constants/Routes.sol";

contract Deploy is Script {
    uint256 public constant WINDOW_LENGTH = 1000;
    address public router;

    string public constant VERIFIED_NAME = "glif.io";
    string public constant VERIFIED_VERSION = "1";

    address public treasury = address(0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // deploys the router
        router = address(new Router(deployerAddr));

        address wFIL = vm.envAddress("WFIL_ADDR");
        address agentFactory = address(new AgentFactory(router));
        address minerRegistry = address(new MinerRegistry(router, IAgentFactory(agentFactory)));
        address poolRegistry = address(
            new PoolRegistry(1e17, deployerAddr, router)
        );
        address agentPolice = address(
            new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, WINDOW_LENGTH, deployerAddr, deployerAddr, router, IPoolRegistry(poolRegistry), IWFIL(wFIL))
        );
        address vcIssuer = vm.envAddress("VC_ISSUER_ADDR");
        address credParser = address(new CredParser());
        address agentDeployer = address(new AgentDeployer());

        Deployer.setupContractRoutes(
            router,
            treasury,
            wFIL,
            minerRegistry,
            agentFactory,
            agentPolice,
            poolRegistry,
            vcIssuer,
            credParser,
            agentDeployer
        );
        vm.stopBroadcast();
    }
}
