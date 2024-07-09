// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Token} from "src/Token/Token.sol";
import {PoolToken} from "shim/PoolToken.sol";
import "./EchidnaConfig.sol";

// Types Interfaces
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPausable} from "src/Types/Interfaces/IPausable.sol";

// Types Structs
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";

import {WFIL} from "shim/WFIL.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {Router} from "src/Router/Router.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
// Constants
import "src/Constants/Routes.sol";
import {EPOCHS_IN_YEAR, EPOCHS_IN_WEEK} from "src/Constants/Epochs.sol";
// Agent
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPoliceV2} from "src/Agent/AgentPoliceV2.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
// Pool
import {InfinityPoolV2} from "src/Pool/InfinityPoolV2.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {IMiniPool} from "src/Types/Interfaces/IMiniPool.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import "test/helpers/Constants.sol";

contract EchidnaSetup is EchidnaConfig {
    Token internal rewardToken;
    PoolToken internal lockToken;

    // Constants
    string internal constant VERIFIED_NAME = "glif.io";
    string internal constant VERIFIED_VERSION = "1";

    // Addresses
    address internal constant ZERO_ADDRESS = address(0);
    uint256 internal DEFAULT_BASE_RATE = FixedPointMathLib.divWadDown(15e16, EPOCHS_IN_YEAR * 1e18);
    address internal constant TREASURY = address(0x40000);
    address internal constant SYSTEM_ADMIN = address(0x50000);
    address internal constant MOCK_ID_STORE_DEPLOYER = address(0xcfa8b8325023C58cdC322a5D3F74d8779d0a5ef5);
    address internal constant INVESTOR = address(0x60000);
    address internal constant RECEIVER = address(0x70000);

    IPool internal pool;
    IPoolToken internal iFIL;
    IWFIL internal wFIL = IWFIL(address(new WFIL(SYSTEM_ADMIN)));
    MockIDAddrStore internal idStore;

    address internal vcIssuer;
    address internal router;
    address internal credParser = address(new CredParser());

    // just used for testing
    uint256 internal vcIssuerPk = 1;

    constructor() {
        rewardToken = new Token("GLIF", "GLF", address(this), address(this));
        lockToken = new PoolToken(address(this));

        vcIssuer = hevm.addr(vcIssuerPk);

        hevm.prank(SYSTEM_ADMIN);
        router = address(new Router(SYSTEM_ADMIN));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        hevm.prank(MOCK_ID_STORE_DEPLOYER);
        idStore = new MockIDAddrStore();

        hevm.prank(SYSTEM_ADMIN);
        address agentFactory = address(new AgentFactory(router));

        // require(
        //     address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore"
        // );

        bytes4[] memory routeIDs = new bytes4[](8);
        address[] memory routeAddrs = new address[](8);

        routeIDs[0] = ROUTE_TREASURY;
        routeAddrs[0] = TREASURY;
        // Add miner registry route
        routeIDs[2] = ROUTE_MINER_REGISTRY;
        hevm.prank(SYSTEM_ADMIN);
        address minerRegistry = address(new MinerRegistry(router, IAgentFactory(agentFactory)));
        routeAddrs[2] = minerRegistry;
        // Add agent factory route
        routeIDs[3] = ROUTE_AGENT_FACTORY;
        routeAddrs[3] = agentFactory;
        // Add vc issuer route
        routeIDs[4] = ROUTE_VC_ISSUER;
        routeAddrs[4] = vcIssuer;
        // Add agent police route
        routeIDs[5] = ROUTE_AGENT_POLICE;
        hevm.prank(SYSTEM_ADMIN);
        address agentPolice =
            address(new AgentPoliceV2(VERIFIED_NAME, VERIFIED_VERSION, SYSTEM_ADMIN, SYSTEM_ADMIN, router));
        routeAddrs[5] = agentPolice;
        // Add cred parser
        routeIDs[6] = ROUTE_CRED_PARSER;
        routeAddrs[6] = credParser;
        // Add agent deployer
        routeIDs[7] = ROUTE_AGENT_DEPLOYER;
        routeAddrs[7] = address(new AgentDeployer());

        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoutes(routeIDs, routeAddrs);

        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).setLevels(levels);

        hevm.roll(block.number + EPOCHS_IN_WEEK);
        pool = createPool();

        // deposit 1 FIL in pool to stop donation attacks
        hevm.deal(INVESTOR, WAD);
        hevm.prank(INVESTOR);
        IPool(address(pool)).deposit{value: WAD}(INVESTOR);
    }

    uint256[10] levels = [
        // in prod, we don't set the 0th level to be max_uint, but we do this in testing to by default allow agents to borrow the max amount
        MAX_UINT256,
        MAX_UINT256 / 9,
        MAX_UINT256 / 8,
        MAX_UINT256 / 7,
        MAX_UINT256 / 6,
        MAX_UINT256 / 5,
        MAX_UINT256 / 4,
        MAX_UINT256 / 3,
        MAX_UINT256 / 2,
        MAX_UINT256
    ];

    // Pool Helpers
    function createPool() internal returns (IPool) {
        iFIL = IPoolToken(address(new PoolToken(SYSTEM_ADMIN)));
        IPool _pool = IPool(
            new InfinityPoolV2(
                SYSTEM_ADMIN,
                router,
                // no min liquidity for test pool
                address(iFIL),
                ZERO_ADDRESS,
                0,
                0
            )
        );
        // the pool starts paused in prod
        hevm.prank(SYSTEM_ADMIN);
        IPausable(address(_pool)).unpause();
        hevm.prank(SYSTEM_ADMIN);
        iFIL.setMinter(address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        iFIL.setBurner(address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(_pool));

        return _pool;
    }
}
