// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {WFIL} from "../src/WFIL.sol";
import {Deployer} from "deploy/Deployer.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {PoolFactory} from "src/Pool/PoolFactory.sol";
import {PowerToken} from "src/PowerToken/PowerToken.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRouter, IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import "src/Constants/Routes.sol";

contract Deploy is Script {
    uint256 public constant WINDOW_LENGTH = 1000;
    address public router;

    string public constant VERIFIED_NAME = "glif.io";
    string public constant VERIFIED_VERSION = "1";

    IMultiRolesAuthority coreAuthority;

    address public treasury = address(0);

    // just used for testing
    uint256 public vcIssuerPk = 1;
    address public vcIssuer;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddr = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        WFIL wFIL = new WFIL();

        // deploys the coreAuthority and the router
        (router, coreAuthority) = Deployer.init(deployerAddr);

        Deployer.setupAdminRoutes(
            address(router),
            deployerAddr,
            deployerAddr,
            deployerAddr,
            deployerAddr,
            deployerAddr,
            deployerAddr,
            deployerAddr,
            deployerAddr
        );

        address minerRegistry = address(new MinerRegistry());
        address agentFactory = address(new AgentFactory());
        address agentPolice = address(
            new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, WINDOW_LENGTH)
        );
        address poolFactory = address(
            new PoolFactory(IERC20(address(wFIL)), 1e17, 0)
        );
        address powerToken = address(new PowerToken());
        address credParser = address(new CredParser());

        vcIssuer = vm.addr(vcIssuerPk);

        Deployer.setupContractRoutes(
            router,
            treasury,
            address(wFIL),
            minerRegistry,
            agentFactory,
            agentPolice,
            poolFactory,
            powerToken,
            vcIssuer,
            credParser
        );

        // any contract that extends RouterAware gets its router set here
        Deployer.setRouterOnContracts(address(router));

        // initialize the system's authentication system
        Deployer.initRoles(router, deployerAddr);

        vm.stopBroadcast();
    }
}
