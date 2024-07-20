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
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPausable} from "src/Types/Interfaces/IPausable.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";

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
import {EPOCHS_IN_YEAR, EPOCHS_IN_WEEK, EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
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
import {MockMiner} from "test/helpers/MockMiner.sol";
import "test/helpers/Constants.sol";

import {IAuth} from "src/Types/Interfaces/IAuth.sol";

contract EchidnaSetup is EchidnaConfig {
    using FixedPointMathLib for uint256;

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
    address internal AGENT_OWNER = address(0x80000);

    IPool internal pool;
    uint256 internal poolID;
    IPoolToken internal iFIL;
    IWFIL internal wFIL = IWFIL(address(new WFIL(SYSTEM_ADMIN)));
    MockIDAddrStore internal idStore;

    address internal vcIssuer;
    address internal router;
    address internal credParser = address(new CredParser());

    // just used for testing
    uint256 internal vcIssuerPk = 1;

    // Declare agentPolice
    address internal agentPolice;

    IAgent internal agent;

    constructor() payable {
        rewardToken = new Token("GLIF", "GLF", address(this), address(this));
        lockToken = new PoolToken(address(this));

        vcIssuer = hevm.addr(vcIssuerPk);

        hevm.prank(SYSTEM_ADMIN);
        router = address(new Router(SYSTEM_ADMIN));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        hevm.prank(MOCK_ID_DEPLOYER);
        idStore = new MockIDAddrStore();
        require(
            address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore"
        );

        hevm.prank(SYSTEM_ADMIN);
        address agentFactory = address(new AgentFactory(router));

        hevm.prank(SYSTEM_ADMIN);
        address minerRegistry = address(new MinerRegistry(router, IAgentFactory(agentFactory)));

        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_MINER_REGISTRY, minerRegistry);

        bytes4[] memory routeIDs = new bytes4[](6);
        address[] memory routeAddrs = new address[](6);

        routeIDs[0] = ROUTE_TREASURY;
        routeAddrs[0] = TREASURY;
        // Add agent factory route
        routeIDs[1] = ROUTE_AGENT_FACTORY;
        routeAddrs[1] = agentFactory;
        // Add vc issuer route
        routeIDs[2] = ROUTE_VC_ISSUER;
        routeAddrs[2] = vcIssuer;
        // Add agent police route
        routeIDs[3] = ROUTE_AGENT_POLICE;
        hevm.prank(SYSTEM_ADMIN);
        agentPolice = address(new AgentPoliceV2(VERIFIED_NAME, VERIFIED_VERSION, SYSTEM_ADMIN, SYSTEM_ADMIN, router));
        routeAddrs[3] = agentPolice;
        // Add cred parser
        routeIDs[4] = ROUTE_CRED_PARSER;
        routeAddrs[4] = credParser;
        // Add agent deployer
        routeIDs[5] = ROUTE_AGENT_DEPLOYER;
        routeAddrs[5] = address(new AgentDeployer());

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
        //@audit =>
        _configureAgent(AGENT_OWNER);
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

    ///////////////////////////////////////////////////////////////////
    /////////////           WRAPPER FUNCTIONS          ////////////////
    ///////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////

    /////////////           INFINITYPOOLV2             ////////////////

    ///////////////////////////////////////////////////////////////////

    // ============================================
    // ==               DEPOSIT                 ==
    // ============================================
    function poolDepositNativeFil(uint256 stakeAmount, address receiver) internal {
        try pool.deposit{value: stakeAmount}(receiver) {
            Debugger.log("pool deposit successful");
        } catch {
            Debugger.log("pool deposit failed");
            assert(false);
        }
    }

    function poolDeposit(uint256 stakeAmount, address receiver) internal {
        try pool.deposit(stakeAmount, receiver) {
            Debugger.log("pool deposit successful");
        } catch {
            Debugger.log("pool deposit failed");
            assert(false);
        }
    }

    function poolDepositNativeFilReverts(uint256 stakeAmount, address receiver) internal {
        try pool.deposit{value: stakeAmount}(receiver) {
            Debugger.log("pool deposit didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool deposit successfully reverted");
        }
    }

    function poolDepositReverts(uint256 stakeAmount, address receiver) internal {
        try pool.deposit(stakeAmount, receiver) {
            Debugger.log("pool deposit didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool deposit successfully reverted");
        }
    }

    function wFilDeposit(uint256 stakeAmount) internal {
        try wFIL.deposit{value: stakeAmount}() {
            Debugger.log("wFil deposit successful");
        } catch {
            Debugger.log("wFil deposit failed");
            assert(false);
        }
    }

    // ============================================
    // ==               WITHDRAW                 ==
    // ============================================

    function poolWithdrawN(uint256 assets, address receiver, address owner) internal {
        try pool.withdraw(assets, receiver, owner) {
            Debugger.log("pool withdraw successful");
        } catch {
            Debugger.log("pool withdraw failed");
            assert(false);
        }
    }

    function poolWithdrawReverts(uint256 assets, address receiver, address owner) internal {
        try pool.withdraw(assets, receiver, owner) {
            Debugger.log("pool withdraw didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool withdraw successfully reverted");
        }
    }

    // ============================================
    // ==               WITHDRAWF                 ==
    // ============================================

    function poolWithdrawF(uint256 assets, address receiver, address owner) internal {
        try pool.withdrawF(assets, receiver, owner) {
            Debugger.log("pool withdrawF successful");
        } catch {
            Debugger.log("pool withdrawF failed");
            assert(false);
        }
    }

    function poolWithdrawFReverts(uint256 assets, address receiver, address owner) internal {
        try pool.withdrawF(assets, receiver, owner) {
            Debugger.log("pool withdrawF didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool withdrawF successfully reverted");
        }
    }

    ///////////////////////////////////////////////////////////////////

    /////////////              AGENT                   ////////////////

    ///////////////////////////////////////////////////////////////////

    // ============================================
    // ==               BORROW                   ==
    // ============================================

    function agentBorrow(uint256 poolid, SignedCredential memory sc) internal {
        try agent.borrow(poolid, sc) {
            Debugger.log("pool borrow successful");
        } catch {
            Debugger.log("pool borrow failed");
            assert(false);
        }
    }

    function agentBorrowRevert(uint256 poolid, SignedCredential memory sc) internal {
        try agent.borrow(poolid, sc) {
            Debugger.log("pool borrow didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool borrow successfully reverted");
        }
    }

    // ============================================
    // ==               PAY                      ==
    // ============================================

    function agentPayRevert(uint256 poolid, SignedCredential memory payCred) internal {
        try agent.pay(poolid, payCred) {
            Debugger.log("pool pay didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool pay successfully reverted");
        }
    }

    function agentPay(uint256 poolid, SignedCredential memory payCred) internal {
        try agent.pay(poolid, payCred) {
            Debugger.log("pool pay successful");
        } catch {
            Debugger.log("pool pay failed");
            assert(false);
        }
    }
    // ============================================
    // ==               HELPERS                 ==
    // ============================================

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
        IRouter(router).pushRoute(ROUTE_POOL_REGISTRY, address(_pool));
        hevm.prank(SYSTEM_ADMIN);
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(_pool));

        return _pool;
    }

    function _configureAgent(address agentOwner) internal returns (IAgent) {
        IMinerRegistry registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
        IAgentFactory agentFactory = IAgentFactory(GetRoute.agentFactory(router));
        agent = IAgent(agentFactory.create(agentOwner, agentOwner, address(0)));

        hevm.prank(AGENT_OWNER);
        MockMiner miner = new MockMiner(AGENT_OWNER);

        uint64 minerID = MockIDAddrStore(MinerHelper.ID_STORE_ADDR).addAddr(address(miner));
        miner.setID(minerID);

        hevm.prank(AGENT_OWNER);
        miner.changeOwnerAddress(address(agent));

        SignedCredential memory addMinerCred = _issueAddMinerCred(agent.id(), minerID);
        // confirm change owner address (agent now owns miner)
        hevm.prank(AGENT_OWNER);
        agent.addMiner(addMinerCred);

        assert(registry.minerRegistered(agent.id(), minerID));

        return agent;
    }

    function _signCred(VerifiableCredential memory vc) internal returns (SignedCredential memory) {
        bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(vcIssuerPk, digest);
        return SignedCredential(vc, v, r, s);
    }

    function _issueAddMinerCred(uint256 agent, uint64 miner) internal returns (SignedCredential memory) {
        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            1000,
            IAgent.addMiner.selector,
            miner,
            // agent data irrelevant for an add miner cred
            bytes("")
        );

        return _signCred(vc);
    }

    function _issueWithdrawCred(uint256 agent, uint256 amount, uint256 principal, uint256 liquidationValue)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = _createAgentData(principal, liquidationValue);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.withdraw.selector,
            // miner data irrelevant for a withdraw cred
            0,
            abi.encode(agentData)
        );

        return _signCred(vc);
    }

    function _issueRemoveMinerCred(uint256 agent, uint64 miner, uint256 principal, uint256 liquidationValue)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = _createAgentData(principal, liquidationValue);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            IAgent.removeMiner.selector,
            miner,
            // agent data irrelevant for an remove miner cred
            abi.encode(agentData)
        );

        return _signCred(vc);
    }

    function _issuePayCred(uint256 agentID, uint256 principal, uint256 collateralValue, uint256 paymentAmount)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = _createAgentData(collateralValue, principal);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agentID,
            block.number,
            block.number + 100,
            paymentAmount,
            IAgent.pay.selector,
            // minerID irrelevant for pay action
            0,
            abi.encode(agentData)
        );

        return _signCred(vc);
    }

    function _issueBorrowCred(uint256 _agent, uint256 principal, uint256 liquidationValue)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = _createAgentData(
            // collateralValue => 2x the borrowAmount
            liquidationValue,
            // principal = borrowAmount
            principal
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            _agent,
            block.number,
            block.number + 100,
            principal,
            IAgent.borrow.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        return _signCred(vc);
    }

    function _createAgentData(uint256 collateralValue, uint256 principal) internal pure returns (AgentData memory) {
        // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
        uint256 lockedFunds = collateralValue * 167 / 100;
        // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
        uint256 agentValue = lockedFunds * 120 / 100;
        return AgentData(
            agentValue,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            // edr not used in in v2
            0,
            // GCRED DEPRECATED
            100,
            // qaPower hardcoded
            10e18,
            principal,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );
    }

    function _getAdjustedRate() internal pure returns (uint256) {
        return FixedPointMathLib.divWadDown(15e34, EPOCHS_IN_YEAR * 1e18);
    }

    function bound(uint256 random, uint256 low, uint256 high) internal pure returns (uint256) {
        return low + random % (high - low);
    }

    function assertApproxEqAbs(uint256 a, uint256 b, uint256 maxDelta) internal {
        uint256 delta = a > b ? a - b : b - a;

        if (delta > maxDelta) {
            Debugger.log("Error: a ~= b not satisfied [uint]");
            Debugger.log("  Expected", b);
            Debugger.log("    Actual", a);
            Debugger.log(" Max Delta", maxDelta);
            Debugger.log("     Delta", delta);
            assert(false);
        }
    }
}
