// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";

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

contract EchidnaInfinityPoolV2 is EchidnaSetup {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

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

    IPool internal pool;
    IPoolToken internal iFIL;
    IWFIL internal wFIL = IWFIL(address(new WFIL(SYSTEM_ADMIN)));
    MockIDAddrStore internal idStore;

    address internal vcIssuer;
    address internal router;
    address internal credParser = address(new CredParser());

    // just used for testing
    uint256 internal vcIssuerPk = 1;

    constructor() payable {
        vcIssuer = hevm.addr(vcIssuerPk);

        hevm.prank(SYSTEM_ADMIN);
        router = address(new Router(SYSTEM_ADMIN));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        hevm.prank(MOCK_ID_STORE_DEPLOYER);
        idStore = new MockIDAddrStore();

        // require(
        //     address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore"
        // );

        hevm.prank(SYSTEM_ADMIN);
        address agentFactory = address(new AgentFactory(router));

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
        hevm.prank(SYSTEM_ADMIN);
        // the pool starts paused in prod
        IPausable(address(_pool)).unpause();
        hevm.prank(SYSTEM_ADMIN);
        iFIL.setMinter(address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        iFIL.setBurner(address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_POOL_REGISTRY, address(_pool));

        return _pool;
    }

    // CoreTestHelper assertions
    function assertPegInTact() internal view {
        IMiniPool _pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));
        uint256 FILtoIFIL = _pool.convertToShares(WAD);
        uint256 IFILtoFIL = _pool.convertToAssets(WAD);
        assert(FILtoIFIL == IFILtoFIL);
        assert(FILtoIFIL == WAD);
        assert(IFILtoFIL == WAD);
    }

    function test_deposit(uint256 stakeAmount) public {
        // first make sure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));
        // here we split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount / 2}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount / 2);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount / 2, INVESTOR);

        assert(wFIL.balanceOf(INVESTOR) + INVESTOR.balance - stakeAmount == investorBalBefore);
        assert(poolBalBefore + stakeAmount == wFIL.balanceOf(address(pool)));
    }

    uint256 constant MAX_FIL = 2e27;
    uint256 constant WAD = 1e18;

    function test_depositBalance(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 0, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount / 2}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount / 2);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount / 2, INVESTOR);

        // Assert that investor and pool balances are as expected
        assert(wFIL.balanceOf(INVESTOR) + INVESTOR.balance - stakeAmount == investorBalBefore);
        assert(poolBalBefore + stakeAmount == wFIL.balanceOf(address(pool)));
    }

    function test_bounddeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is sufficiently funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorFILBalStart = INVESTOR.balance;
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        assertPegInTact();

        // Check wFIL invariant
        // assert(investorWFILBalStart + poolWFILBalStart == wFIL.totalSupply());
    }

    function test_fuzz_depositZeroReverts(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 0, 1); // Force stakeAmount to 0

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing 0 reverts
        hevm.prank(INVESTOR);
        (bool success,) =
            address(pool).call{value: stakeAmount}(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);

        hevm.prank(INVESTOR);
        (success,) = address(pool).call(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    function test_fuzz_depositMoreThanBalanceReverts(uint256 stakeAmount) public {
        // Ensure stakeAmount is between 1.5 and 2 times MAX_FIL to force the condition
        stakeAmount = bound(stakeAmount, MAX_FIL + 1, MAX_FIL * 2);

        // Ensure the investor is funded with sufficient balance for deposits
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing more than the available balance reverts
        hevm.prank(INVESTOR);
        (bool success,) =
            address(pool).call{value: stakeAmount}(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    function test_fuzz_approveMoreThanBalanceReverts(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MAX_FIL + 1, MAX_FIL * 2); // Force stakeAmount to more than the balance

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that approving more than the balance reverts
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    function test_fuzz_sharesReceivedAfterDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        // Deposit wFIL
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        uint256 sharesReceived = pool.deposit{value: stakeAmount}(INVESTOR);

        // Assert shares received and balance changes
        assert(sharesReceived == stakeAmount);
        assert(iFIL.balanceOf(INVESTOR) - investorIFILBalStart == sharesReceived);
    }

    function test_fuzz_filiFILProportion(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL); // Ensure stakeAmount is not 0

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Get initial iFIL balance of investor
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        // Deposit wFIL
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Get final iFIL balance of investor
        uint256 investorIFILBalEnd = iFIL.balanceOf(INVESTOR);

        // Assert the final balance is greater than the initial balance
        assert(investorIFILBalEnd > investorIFILBalStart);

        // Verify FIL and iFIL proportions
        uint256 assetsConverted = pool.convertToAssets(investorIFILBalEnd);
        uint256 sharesConverted = pool.convertToShares(investorIFILBalEnd - investorIFILBalStart);

        // Assert the converted assets and shares
        assert(assetsConverted == investorIFILBalEnd);
        assert(sharesConverted == (investorIFILBalEnd - investorIFILBalStart));
    }

    function bound(uint256 random, uint256 low, uint256 high) public pure returns (uint256) {
        return low + random % (high - low);
    }
}
