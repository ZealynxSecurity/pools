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
import "src/Types/Structs/Credentials.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";

import {WFIL} from "shim/WFIL.sol";
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
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {FinMath} from "src/Pool/FinMath.sol";

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
        poolID = pool.id();
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

    function agentBorrow(address agent, SignedCredential memory sc) internal {
        try IAgent(agent).borrow(poolID, sc) {
            Debugger.log("pool borrow successful");
        } catch {
            Debugger.log("pool borrow failed");
            assert(false);
        }
    }

    function agentBorrowRevert(address agent, SignedCredential memory sc) internal {
        try IAgent(agent).borrow(poolID, sc) {
            Debugger.log("pool borrow didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool borrow successfully reverted");
        }
    }

    // ============================================
    // ==               PAY                      ==
    // ============================================


    // ============================================
    // ==               HELPERS                 ==
    // ============================================

    // Pool Helpers
    function createPool() internal returns (IPool) {
        Debugger.log("Creating pool");
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
        Debugger.log("Pool created");

        return _pool;
    }

    function _loadApproveWFIL(uint256 amount, address investor) internal {
        hevm.deal(investor, amount);
        hevm.prank(investor);
        wFilDeposit(amount);
        hevm.prank(investor);
        wFIL.approve(address(pool), amount);
    }

    function simulateEarnings(uint256 earnAmount) internal {
        address donator = USER1;
        hevm.deal(donator, earnAmount);
        hevm.prank(donator);
        wFilDeposit(earnAmount);
        hevm.prank(donator);
        wFIL.transfer(address(pool), earnAmount);
    }

    function issueGenericSetDefaultCred(uint256 agent, uint256 principal) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        hevm.roll(block.number + 1);

        // create a cred where DTL >100%
        uint256 collateralValue = 0;

        AgentData memory ad = AgentData(
            1e18,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            0,
            0,
            // qaPower hardcoded
            0,
            principal,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            IAgentPolice.setAgentDefaultDTL.selector,
            // minerID irrelevant for setDefault action
            0,
            abi.encode(ad)
        );

        return signCred(vc);
    }

    function signCred(VerifiableCredential memory vc) internal returns (SignedCredential memory) {
        bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(vcIssuerPk, digest);
        return SignedCredential(vc, v, r, s);
    }

    function _depositFundsIntoPool(uint256 amount, address investor) internal {
        hevm.deal(investor, amount);
        address _pool = address(GetRoute.pool(GetRoute.poolRegistry(router), 0));
        IERC4626 pool4626 = IERC4626(address(_pool));

        // `investor` stakes `amount` FIL
        hevm.prank(investor);
        wFIL.deposit{value: amount}();
        hevm.prank(investor);
        wFIL.approve(address(_pool), amount);
        hevm.prank(investor);
        pool4626.deposit(amount, investor);
    }

    // this is a helper function to allow us to issue a borrow cred without rolling forward
    function _issueGenericBorrowCred(uint256 _agent, uint256 amount) internal returns (SignedCredential memory) {
        AgentData memory agentData = createAgentData(
            // collateralValue => 2x the borrowAmount
            amount * 2
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            _agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.borrow.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function createAgentData(uint256 collateralValue) internal pure returns (AgentData memory) {
        // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
        uint256 lockedFunds = collateralValue * 167 / 100;
        // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
        uint256 agentValue = lockedFunds * 120 / 100;
        return AgentData(
            agentValue,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            // edr
            0,
            // GCRED DEPRECATED
            100,
            // qaPower hardcoded
            10e18,
            // principal
            0,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );
    }

    function calculateInterestOwed(uint256 borrowAmount, uint256 rollFwdAmt, uint256 perEpochRate)
        internal
        pure
        returns (uint256 interestOwed, uint256 interestOwedPerEpoch)
    {
        // note we add 1 more bock of interest owed to account for the roll forward of 1 epoch inside agentBorrow helper
        // since borrowAmount is also WAD based, the _interestOwedPerEpoch is also WAD based (e18 * e18 / e18)
        uint256 _interestOwedPerEpoch = borrowAmount.mulWadUp(perEpochRate);
        // _interestOwedPerEpoch is mulWadUp by epochs (not WAD based), which cancels the WAD out for interestOwed
        interestOwed = (_interestOwedPerEpoch.mulWadUp(rollFwdAmt));
        // when setting the interestOwedPerEpoch, we div out the WAD manually here
        // we'd rather use the more precise _interestOwedPerEpoch to compute interestOwed above
        interestOwedPerEpoch = _interestOwedPerEpoch / WAD;
    }

    function _issuePayCred(uint256 agentID, uint256 collateralValue, uint256 paymentAmount)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = createAgentData(collateralValue);

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

        return signCred(vc);
    }

    function _issueGenericPayCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        return _issuePayCred(agent, amount * 2, amount);
    }

    function _agentOwner(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).owner();
    }

    function agentBorrowLogic(IAgent agent, SignedCredential memory sc) internal {
        _fundAgentsMiners(agent, sc.vc);

        uint256 preTotalBorrowed = pool.totalBorrowed();

        hevm.prank(_agentOwner(agent));
        // Establsh the state before the borrow
        StateSnapshot memory preBorrowState = _snapshot(address(agent));
        hevm.prank(_agentOwner(agent));
        Account memory account = AccountHelpers.getAccount(router, address(agent), poolID);
        uint256 borrowBlock = block.number;
        hevm.prank(_agentOwner(agent));
        agent.borrow(poolID, sc);

        // Check the state after the borrow
        uint256 currentAgentBal = wFIL.balanceOf(address(agent));
        uint256 currentPoolBal = wFIL.balanceOf(address(pool));
        assert(currentAgentBal == preBorrowState.agentBalanceWFIL + sc.vc.value);
        assert(currentPoolBal == preBorrowState.poolBalanceWFIL - sc.vc.value);

        account = AccountHelpers.getAccount(router, address(agent), poolID);

        // first time borrowing, check the startEpoch
        if (preBorrowState.agentBorrowed == 0) {
            assert(account.startEpoch == borrowBlock);
            assert(account.epochsPaid == borrowBlock);
        }

        if (!account.defaulted) {
            assert(account.principal == preBorrowState.agentBorrowed + sc.vc.value);
            assert(
                pool.getAgentBorrowed(agent.id()) - preBorrowState.agentBorrowed
                    == currentAgentBal - preBorrowState.agentBalanceWFIL
            );
            assert(pool.totalBorrowed() == preTotalBorrowed + currentAgentBal - preBorrowState.agentBalanceWFIL);
        }
    }

    function _fundAgentsMiners(IAgent agent, VerifiableCredential memory vc) internal {
        // when we borrow or remove equity, we need to make sure we put enough funds on the agent to match the agent total value or else the borrow will fail
        // to not interfere with other calls, we put the funds on the agent's first miner
        uint256 agentTotalValue = MAX_FIL / 4; // vc.getCollateralValue(credParser);
        uint256 minerID = GetRoute.minerRegistry(router).getMiner(vc.subject, 0);
        // fund this miner with the required agent's total value
        if (agentTotalValue > agent.liquidAssets()) {
            // deal some balance to the miner
            address miner = address(bytes20(abi.encodePacked(hex"ff0000000000000000000000", uint64(minerID))));
            hevm.deal(miner, agentTotalValue - agent.liquidAssets());
        }
    }

    function borrowRollFwdAndPay(
        IAgent _agent,
        SignedCredential memory borrowCred,
        uint256 payAmount,
        uint256 rollFwdAmt
    ) internal returns (StateSnapshot memory) {
        uint256 agentID = _agent.id();
        agentBorrowLogic(_agent, borrowCred);

        hevm.roll(block.number + rollFwdAmt);

        (, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState) =
            _agentPay(_agent, _issueGenericPayCred(agentID, payAmount), _getAdjustedRate());

        assertPmtSuccess(_agent, prePayState, payAmount, principalPaid, refund);

        return prePayState;
    }

    function _agentPay(IAgent _agent, SignedCredential memory sc, uint256 perEpochRate)
        internal
        returns (uint256 epochsPaid, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState)
    {
        hevm.prank(address(_agent));
        hevm.deal(address(_agent), sc.vc.value);
        hevm.prank(address(_agent));
        wFIL.deposit{value: sc.vc.value}();
        hevm.prank(address(_agent));
        wFIL.approve(address(pool), sc.vc.value);

        uint256 prePayEpochsPaid = AccountHelpers.getAccount(router, address(_agent), poolID).epochsPaid;

        prePayState = _snapshot(address(_agent));

        hevm.prank(_agentOperator(_agent));
        uint256 totalDebt = _agentDebt(_agent, perEpochRate);
        hevm.prank(_agentOperator(_agent));
        (, epochsPaid, principalPaid, refund) = _agent.pay(poolID, sc);

        Account memory account = AccountHelpers.getAccount(router, address(_agent), poolID);

        if (sc.vc.value >= totalDebt) {
            assert(account.epochsPaid == 0);
            assert(account.principal == 0);
        } else {
            assert(account.principal > 0);
            assert(account.epochsPaid > prePayEpochsPaid);
        }
    }

    function _agentDebt(IAgent agent, uint256 perEpochRate) internal view returns (uint256) {
        return _agentDebt(agent.id(), perEpochRate);
    }

    function _agentDebt(uint256 agentID, uint256 perEpochRate) internal view returns (uint256) {
        return FinMath.computeDebt(AccountHelpers.getAccount(router, agentID, 0), perEpochRate);
    }

    function _agentOperator(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).operator();
    }

    function _snapshot(address agent) internal view returns (StateSnapshot memory snapshot) {
        Account memory account = AccountHelpers.getAccount(router, agent, poolID);
        snapshot.agentBalanceWFIL = wFIL.balanceOf(agent);
        snapshot.poolBalanceWFIL = wFIL.balanceOf(address(pool));
        snapshot.agentBorrowed = account.principal;
        snapshot.accountEpochsPaid = account.epochsPaid;
    }

    function assertPmtSuccess(
        IAgent newAgent,
        StateSnapshot memory prePayState,
        uint256 payAmount,
        uint256 principalPaid,
        uint256 refund
    ) internal {
        assert(prePayState.poolBalanceWFIL + payAmount == wFIL.balanceOf(address(pool)));
        assert(prePayState.agentBalanceWFIL - payAmount == wFIL.balanceOf(address(newAgent)));

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, newAgent.id(), pool.id());

        // full exit
        if (principalPaid >= prePayState.agentBorrowed) {
            // refund should be greater than 0 if too much principal was paid
            if (principalPaid > prePayState.agentBorrowed) {
                assert(principalPaid - refund == prePayState.agentBorrowed);
            }

            assert(postPaymentAccount.principal == 0);
            assert(postPaymentAccount.epochsPaid == 0);
            assert(postPaymentAccount.startEpoch == 0);
        } else {
            // partial exit or interest only payment
            assert(postPaymentAccount.epochsPaid > prePayState.accountEpochsPaid);
            assert(postPaymentAccount.epochsPaid <= block.number);
        }
    }

    function _setAgentDefaulted(IAgent agent, uint256 principal) internal {
        IAgentPolice police = GetRoute.agentPolice(router);
        uint256 agentID = agent.id();
        SignedCredential memory defaultCred = issueGenericSetDefaultCred(agentID, principal);

        hevm.prank(IAuth(address(police)).owner());
        police.setAgentDefaultDTL(address(agent), defaultCred);

        assert(agent.defaulted());
    }

    function _setAgentDefaulted(IAgent agent, uint256 principal, uint256 liquidationValue) internal {
        IAgentPolice police = GetRoute.agentPolice(router);
        uint256 agentID = agent.id();
        SignedCredential memory defaultCred = issueGenericSetDefaultCred(agentID, principal);

        SignedCredential memory borrowCred = _issueBorrowCred(agentID, principal, liquidationValue);

        Debugger.log("Before agentBorrow");

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(agent), borrowCred);

        Debugger.log("After agentBorrow");

        hevm.prank(IAuth(address(police)).owner());
        police.setAgentDefaultDTL(address(agent), defaultCred);

        assert(agent.defaulted());
    }

    function _configureAgent(address agentOwner) internal returns (IAgent agent) {
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
        require(low < high, "Invalid range");

        if (low == high - 1) {
            return low;
        }

        uint256 range = high - low;
        uint256 result = low + (random % range);

        if (low > 0 && result == 0) {
            result = low;
        }

        return result;
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
