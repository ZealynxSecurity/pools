// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {WFIL} from "../src/WFIL.sol";
import {Deployer} from "deploy/Deployer.sol";
import {Router} from "src/Router/Router.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {PoolFactory} from "src/Pool/PoolFactory.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRouter, IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
import "src/Constants/Routes.sol";

contract Deploy is Script {
    uint256 public constant WINDOW_LENGTH = 1000;
    address public router;

    string public constant VERIFIED_NAME = "glif.io";
    string public constant VERIFIED_VERSION = "1";

    address public treasury = address(0);

    // just used for testing
    uint256 public vcIssuerPk = 1;
    address public vcIssuer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        WFIL wFIL = new WFIL();

        // deploys the router
        router = address(new Router(deployerAddr));

        address minerRegistry = address(new MinerRegistry(router));
        address agentFactory = address(new AgentFactory(router));
        address agentPolice = address(
            new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, WINDOW_LENGTH, deployerAddr, deployerAddr, router)
        );
        address poolFactory = address(
            new PoolFactory(IERC20(address(wFIL)), 1e17, 0, deployerAddr, deployerAddr, router)
        );
        address credParser = address(new CredParser());
        address agentDeployer = address(new AgentDeployer());

        vcIssuer = vm.addr(vcIssuerPk);

        Deployer.setupContractRoutes(
            router,
            treasury,
            address(wFIL),
            minerRegistry,
            agentFactory,
            agentPolice,
            poolFactory,
            vcIssuer,
            credParser,
            agentDeployer
        );
        vm.stopBroadcast();
    }
}
