// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "test/helpers/MockMiner.sol";
import {PoolToken} from "shim/PoolToken.sol";
import {WFIL} from "shim/WFIL.sol";
import {InfinityPool} from "src/Pool/InfinityPool.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Deployer} from "deploy/Deployer.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolRegistry} from "src/Pool/PoolRegistry.sol";
import {Router} from "src/Router/Router.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";
import {EPOCHS_IN_WEEK, EPOCHS_IN_DAY, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {errorSelector} from "./helpers/Utils.sol";

import "src/Constants/Routes.sol";

struct StateSnapshot {
    uint256 agentBalanceWFIL;
    uint256 poolBalanceWFIL;
    uint256 agentBorrowed;
    uint256 agentPoolBorrowCount;
    uint256 accountEpochsPaid;
}

error Unauthorized();
error InvalidParams();
error InsufficientLiquidity();
error InsufficientCollateral();
error InvalidCredential();

uint256 constant WAD = 1e18;
// max FIL value - 2B atto
uint256 constant MAX_FIL = 2e27;
uint256 constant DUST = 10000;
uint256 constant MAX_UINT256 = type(uint256).max;

contract BaseTest is Test {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    address public constant ZERO_ADDRESS = address(0);
    uint256 public DEFAULT_BASE_RATE = FixedPointMathLib.divWadDown(15e16, EPOCHS_IN_YEAR * 1e18);
    address public treasury = makeAddr("TREASURY");
    address public router;
    address public systemAdmin = makeAddr("SYSTEM_ADMIN");

    // just used for testing
    uint256 public vcIssuerPk = 1;
    address public vcIssuer;

    string constant VERIFIED_NAME = "glif.io";
    string constant VERIFIED_VERSION = "1";

    WFIL wFIL = new WFIL(systemAdmin);
    MockIDAddrStore idStore;
    address credParser = address(new CredParser());

    constructor() {
        vm.startPrank(systemAdmin);
        // deploys the router
        router = address(new Router(systemAdmin));
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        address agentFactory = address(new AgentFactory(router));
        // 1e17 = 10% treasury fee on yield
        address poolRegistry = address(new PoolRegistry(10e16, systemAdmin, router));

        vcIssuer = vm.addr(vcIssuerPk);
        Deployer.setupContractRoutes(
            address(router),
            treasury,
            address(wFIL),
            address(new MinerRegistry(router, IAgentFactory(agentFactory))),
            agentFactory,
            address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, systemAdmin, systemAdmin, router)),
            poolRegistry,
            vcIssuer,
            credParser,
            address(new AgentDeployer())
        );

        GetRoute.agentPolice(router).setLevels(levels);
        // roll forward at least 1 week so our computations dont overflow/underflow
        vm.roll(block.number + EPOCHS_IN_WEEK);

        // deploy an ID address store for mocking built-in miner actors
        idStore = new MockIDAddrStore();
        require(
            address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore"
        );
        vm.stopPrank();
    }

    function configureAgent(address minerOwner) public returns (Agent, uint64 minerID) {
        uint64 miner = _newMiner(minerOwner);
        // create an agent for miner
        Agent agent = _configureAgent(minerOwner, miner);
        return (agent, miner);
    }

    function _configureAgent(address minerOwner, uint64 miner) public returns (Agent agent) {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.startPrank(minerOwner);
        agent = Agent(payable(agentFactory.create(minerOwner, minerOwner, makeAddr("ADO_REQUEST_KEY"))));
        assertTrue(miner.isOwner(minerOwner), "The mock miner's current owner should be set to the original owner");
        vm.stopPrank();

        _agentClaimOwnership(address(agent), miner, minerOwner);
        return agent;
    }

    function configureMiner(address _agent, address minerOwner) public returns (uint64 miner) {
        miner = _newMiner(minerOwner);
        _agentClaimOwnership(address(_agent), miner, minerOwner);
    }

    function _newMiner(address minerOwner) internal returns (uint64 id) {
        vm.prank(minerOwner);
        MockMiner miner = new MockMiner(minerOwner);

        id = MockIDAddrStore(MinerHelper.ID_STORE_ADDR).addAddr(address(miner));
        miner.setID(id);
    }

    function _agentClaimOwnership(address _agent, uint64 _miner, address _minerOwner) internal {
        IMinerRegistry registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
        IAgent agent = IAgent(_agent);

        vm.startPrank(_minerOwner);
        _miner.changeOwnerAddress(address(_agent));
        vm.stopPrank();

        SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), _miner);
        // confirm change owner address (agent now owns miner)
        vm.startPrank(_minerOwner);
        agent.addMiner(addMinerCred);
        vm.stopPrank();

        assertTrue(_miner.isOwner(_agent), "The mock miner's owner should change to the agent");
        assertTrue(
            registry.minerRegistered(agent.id(), _miner),
            "After adding the miner the registry should have the miner's address as a registered miner"
        );
    }

    function issueAddMinerCred(uint256 agent, uint64 miner) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            1000,
            Agent.addMiner.selector,
            miner,
            // agent data irrelevant for an add miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issueWithdrawCred(uint256 agent, uint256 amount, AgentData memory agentData)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            Agent.withdraw.selector,
            // miner data irrelevant for a withdraw cred
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issueRemoveMinerCred(uint256 agent, uint64 miner, AgentData memory agentData)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            Agent.removeMiner.selector,
            miner,
            // agent data irrelevant for an remove miner cred
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issuePullFundsCred(uint256 agent, uint64 miner, uint256 amount)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            Agent.pullFunds.selector,
            miner,
            // agent data irrelevant for an pull funds from miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issuePushFundsCred(uint256 agent, uint64 miner, uint256 amount)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            Agent.pushFunds.selector,
            miner,
            // agent data irrelevant for an push funds to miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issueGenericPayCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);
        return _issueGenericPayCred(agent, amount);
    }

    function _issueGenericPayCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        AgentData memory agentData = createAgentData(
            // collateralValue => 2x the borrowAmount
            amount * 2,
            // good EDR
            1000,
            // principal = borrowAmount
            amount
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            Agent.pay.selector,
            // minerID irrelevant for pay action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issueGenericRecoverCred(uint256 agent, uint256 faultySectors, uint256 liveSectors)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = AgentData(
            0,
            0,
            0,
            0,
            // perfect gcred
            100,
            0,
            0,
            // faulty sectors
            faultySectors,
            // livesectors
            liveSectors,
            0
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            Agent.setRecovered.selector,
            // minerID irrelevant for setRecovered action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issueGenericSetDefaultCred(uint256 agent, uint256 principal) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

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
            AgentPolice.setAgentDefaultDTL.selector,
            // minerID irrelevant for setDefault action
            0,
            abi.encode(ad)
        );

        return signCred(vc);
    }

    function issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);
        return _issueGenericBorrowCred(agent, amount);
    }

    // this is a helper function to allow us to issue a borrow cred without rolling forward
    function _issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        uint256 principal = amount;
        // NOTE: since we don't pull this off the pool it could be out of sync - careful
        uint256 adjustedRate = _getAdjustedRate();
        AgentData memory agentData = createAgentData(
            // collateralValue => 2x the borrowAmount
            amount * 2,
            // good EDR (5x expected payments)
            (adjustedRate * EPOCHS_IN_DAY * principal * 5) / WAD,
            // principal = borrowAmount
            principal
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            Agent.borrow.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function createAgentData(uint256 collateralValue, uint256 expectedDailyRewards, uint256 principal)
        internal
        pure
        returns (AgentData memory)
    {
        // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
        uint256 lockedFunds = collateralValue * 167 / 100;
        // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
        uint256 agentValue = lockedFunds * 120 / 100;
        return AgentData(
            agentValue,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            expectedDailyRewards,
            0,
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

    function emptyAgentData() internal pure returns (AgentData memory) {
        return AgentData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function signCred(VerifiableCredential memory vc) public returns (SignedCredential memory) {
        bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
        return SignedCredential(vc, v, r, s);
    }

    function createPool() internal returns (IPool pool) {
        IPoolRegistry poolRegistry = GetRoute.poolRegistry(router);
        PoolToken liquidStakingToken = new PoolToken(systemAdmin);
        pool = IPool(
            new InfinityPool(
                systemAdmin,
                router,
                // no min liquidity for test pool
                address(liquidStakingToken),
                ILiquidityMineSP(address(0)),
                0,
                GetRoute.poolRegistry(router).allPoolsLength()
            )
        );
        vm.prank(systemAdmin);
        liquidStakingToken.setMinter(address(pool));
        vm.startPrank(systemAdmin);
        poolRegistry.attachPool(pool);
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(pool));
        vm.stopPrank();
    }

    function createAndFundPool(uint256 amount, address investor) internal returns (IPool pool) {
        pool = createPool();
        depositFundsIntoPool(pool, amount, investor);
    }

    function poolBasicSetup(uint256 stakeAmount, uint256 borrowAmount, address investor1, address minerOwner)
        internal
        returns (
            IPool pool,
            Agent agent,
            uint64 miner,
            SignedCredential memory borrowCredBasic,
            VerifiableCredential memory vcBasic
        )
    {
        pool = createAndFundPool(stakeAmount, investor1);
        (agent, miner) = configureAgent(minerOwner);
        borrowCredBasic = issueGenericBorrowCred(agent.id(), borrowAmount);
        vcBasic = borrowCredBasic.vc;
    }

    function createAccount(uint256 amount) internal view returns (Account memory account) {
        uint256 currentBlock = block.number;
        account = Account(currentBlock, amount, currentBlock, false);
    }

    function depositFundsIntoPool(IPool pool, uint256 amount, address investor) internal {
        IERC4626 pool4626 = IERC4626(address(pool));
        // `investor` stakes `amount` FIL
        vm.deal(investor, amount);
        vm.startPrank(investor);
        wFIL.deposit{value: amount}();
        wFIL.approve(address(pool), amount);
        pool4626.deposit(amount, investor);
        vm.stopPrank();
    }

    function agentBorrow(IAgent agent, uint256 poolID, SignedCredential memory sc) internal {
        IPool pool = GetRoute.pool(GetRoute.poolRegistry(router), poolID);
        uint256 preTotalBorrowed = pool.totalBorrowed();
        testInvariants(pool, "agentBorrow Start");
        vm.startPrank(_agentOwner(agent));
        // Establsh the state before the borrow
        StateSnapshot memory preBorrowState = _snapshot(address(agent), poolID);
        Account memory account = AccountHelpers.getAccount(router, address(agent), poolID);
        uint256 borrowBlock = block.number;
        agent.borrow(poolID, sc);

        vm.stopPrank();
        // Check the state after the borrow
        uint256 currentAgentBal = wFIL.balanceOf(address(agent));
        uint256 currentPoolBal = wFIL.balanceOf(address(GetRoute.pool(GetRoute.poolRegistry(router), poolID)));
        assertEq(currentAgentBal, preBorrowState.agentBalanceWFIL + sc.vc.value, "Agent's balance should increase");
        assertEq(currentPoolBal, preBorrowState.poolBalanceWFIL - sc.vc.value, "Pool's balance should decrease");

        account = AccountHelpers.getAccount(router, address(agent), poolID);

        // first time borrowing, check the startEpoch
        if (preBorrowState.agentBorrowed == 0) {
            assertEq(account.startEpoch, borrowBlock, "Account startEpoch should be correct");
            assertEq(account.epochsPaid, borrowBlock, "Account epochsPaid should be correct");
        }

        if (!account.defaulted) {
            assertEq(
                account.principal, preBorrowState.agentBorrowed + sc.vc.value, "Account principal should be correct"
            );
            assertEq(
                pool.getAgentBorrowed(agent.id()) - preBorrowState.agentBorrowed,
                currentAgentBal - preBorrowState.agentBalanceWFIL,
                "Pool agentBorrowed should increase by the right amount"
            );
            assertEq(
                pool.totalBorrowed(),
                preTotalBorrowed + currentAgentBal - preBorrowState.agentBalanceWFIL,
                "Pool totalBorrowed should be correct"
            );
        }
        testInvariants(pool, "agentBorrow End");
    }

    function agentPay(IAgent agent, IPool pool, SignedCredential memory sc)
        internal
        returns (
            uint256 rate,
            uint256 epochsPaid,
            uint256 principalPaid,
            uint256 refund,
            StateSnapshot memory prePayState
        )
    {
        testInvariants(pool, "agentPay Start");
        vm.startPrank(address(agent));
        vm.deal(address(agent), sc.vc.value);
        wFIL.deposit{value: sc.vc.value}();
        wFIL.approve(address(pool), sc.vc.value);
        vm.stopPrank();

        vm.startPrank(_agentOperator(agent));

        Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

        uint256 prePayEpochsPaid = account.epochsPaid;

        prePayState = _snapshot(address(agent), pool.id());

        uint256 totalDebt = pool.getAgentDebt(agent.id());

        (rate, epochsPaid, principalPaid, refund) = agent.pay(pool.id(), sc);

        vm.stopPrank();

        account = AccountHelpers.getAccount(router, address(agent), pool.id());

        assertGt(rate, 0, "Should not have a 0 rate");

        if (sc.vc.value >= totalDebt) {
            assertEq(
                account.epochsPaid,
                0,
                "Should have 0 epochs paid if there was a refund - meaning all principal was paid"
            );
            assertEq(
                account.principal, 0, "Should have 0 principal if there was a refund - meaning all principal was paid"
            );
        } else {
            assertGt(account.principal, 0, "Should have some principal left");
            assertGt(account.epochsPaid, prePayEpochsPaid, "Should have paid more epochs");
        }

        testInvariants(pool, "agentPay End");
    }

    function assertPegInTact(IPool pool) internal {
        uint256 FILtoIFIL = pool.convertToShares(WAD);
        uint256 IFILtoFIL = pool.convertToAssets(WAD);
        assertEq(FILtoIFIL, IFILtoFIL, "Peg should be 1:1");
        assertEq(FILtoIFIL, WAD, "Peg should be 1:1");
        assertEq(IFILtoFIL, WAD, "Peg should be 1:1");
    }

    function calculateInterestOwed(uint256 borrowAmount, uint256 rollFwdAmt)
        internal
        view
        returns (uint256 interestOwed, uint256 interestOwedPerEpoch)
    {
        // since gcred is hardcoded in the credential, we know the rate ahead of time (rate does not change if gcred does not change, even if other financial statistics change)
        // rate here is WAD based
        uint256 rate = IPool(IRouter(router).getRoute(ROUTE_INFINITY_POOL)).getRate();
        // note we add 1 more bock of interest owed to account for the roll forward of 1 epoch inside agentBorrow helper
        // since borrowAmount is also WAD based, the _interestOwedPerEpoch is also WAD based (e18 * e18 / e18)
        uint256 _interestOwedPerEpoch = borrowAmount.mulWadUp(rate);
        // _interestOwedPerEpoch is mulWadUp by epochs (not WAD based), which cancels the WAD out for interestOwed
        interestOwed = (_interestOwedPerEpoch.mulWadUp(rollFwdAmt));
        // when setting the interestOwedPerEpoch, we div out the WAD manually here
        // we'd rather use the more precise _interestOwedPerEpoch to compute interestOwed above
        interestOwedPerEpoch = _interestOwedPerEpoch / WAD;
    }

    function putAgentOnAdministration(
        IAgent agent,
        address administration,
        uint256 rollFwdPeriod,
        uint256 borrowAmount,
        uint256 poolID
    ) internal {
        IAgentPolice police = GetRoute.agentPolice(router);
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, poolID, borrowCred);

        vm.roll(block.number + rollFwdPeriod);

        vm.startPrank(IAuth(address(police)).owner());
        police.putAgentOnAdministration(address(agent), administration);
        vm.stopPrank();

        assertEq(agent.administration(), administration);
    }

    function setAgentDefaulted(IAgent agent, uint256 principal) internal {
        IAgentPolice police = GetRoute.agentPolice(router);
        SignedCredential memory defaultCred = issueGenericSetDefaultCred(agent.id(), principal);

        // set an account in storage with some principal
        agentBorrow(agent, 0, issueGenericBorrowCred(agent.id(), principal));

        vm.startPrank(IAuth(address(police)).owner());
        police.setAgentDefaultDTL(address(agent), defaultCred);
        vm.stopPrank();

        testInvariants(IPool(IRouter(router).getRoute(ROUTE_INFINITY_POOL)), "setAgentDefaultDTL");

        assertTrue(agent.defaulted(), "Agent should be put into default");
    }

    function _borrowedPoolsCount(uint256 agentID) internal view returns (uint256) {
        return GetRoute.poolRegistry(router).poolIDs(agentID).length;
    }

    function _agentOwner(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).owner();
    }

    function _agentOperator(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).operator();
    }

    function _snapshot(address agent, uint256 poolID) internal view returns (StateSnapshot memory snapshot) {
        Account memory account = AccountHelpers.getAccount(router, agent, poolID);
        snapshot.agentBalanceWFIL = wFIL.balanceOf(agent);
        snapshot.poolBalanceWFIL = wFIL.balanceOf(address(GetRoute.pool(GetRoute.poolRegistry(router), poolID)));
        snapshot.agentBorrowed = account.principal;
        snapshot.accountEpochsPaid = account.epochsPaid;
        snapshot.agentPoolBorrowCount = _borrowedPoolsCount(IAgent(agent).id());
    }

    function _getAdjustedRate() internal pure returns (uint256) {
        return FixedPointMathLib.divWadDown(15e34, EPOCHS_IN_YEAR * 1e18);
    }

    function testInvariants(IPool pool, string memory label) internal {
        _invIFILWorthAssetsOfPool(pool, label);
    }

    function _invIFILWorthAssetsOfPool(IPool pool, string memory label) internal {
        uint256 MAX_PRECISION_DELTA = 1;
        // this invariant knows that iFIL should represent the total value of the pool, which is composed of:
        // 1. all funds given to miners + agents
        // 2. balance of wfil held by the pool
        // 3. minus any fees held temporarily by the pool
        uint256 agentCount = GetRoute.agentFactory(router).agentCount();

        uint256 totalDebtFromAccounts = 0;
        uint256 totalInterestFromAccounts = 0;
        uint256 totalBorrowedFromAccounts = 0;

        for (uint256 i = 1; i <= agentCount; i++) {
            Account memory account = AccountHelpers.getAccount(router, i, pool.id());
            // the invariant breaks when an account is in default, we no longer expect to get that amount back
            if (!account.defaulted) {
                totalBorrowedFromAccounts += pool.getAgentBorrowed(i);
                totalDebtFromAccounts += pool.getAgentDebt(i);
                totalInterestFromAccounts += pool.getAgentInterestOwed(i);
            }
        }

        // the difference between what our current debt is and what we've borrowed is the total amount we've accrued
        // we add back what had paid in interest to get the total amount of rewards we've accrued
        uint256 accruedRewards = totalDebtFromAccounts - totalBorrowedFromAccounts + pool.lpRewards().paid;
        uint256 accruedRewards2 = totalInterestFromAccounts + pool.lpRewards().paid;

        assertEq(
            accruedRewards,
            accruedRewards2,
            string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: accrued rewards calculations should match"))
        );

        assertApproxEqAbs(
            accruedRewards,
            pool.lpRewards().accrued,
            MAX_PRECISION_DELTA,
            string(
                abi.encodePacked(
                    label,
                    " _invIFILWorthAssetsOfPool: accrued rewards in each account should match total pool accrued rewards"
                )
            )
        );

        uint256 poolAssets = wFIL.balanceOf(address(pool));

        // if we take the total supply of iFIL and convert it to assets, we should get the total pools assets + lent out funds
        uint256 totalIFILSupply = pool.liquidStakingToken().totalSupply();

        assertApproxEqAbs(
            poolAssets + totalDebtFromAccounts - pool.treasuryFeesOwed(),
            pool.totalAssets(),
            MAX_PRECISION_DELTA,
            string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: pool total assets invariant wrong"))
        );
        assertApproxEqAbs(
            pool.convertToAssets(totalIFILSupply),
            poolAssets + totalDebtFromAccounts - pool.treasuryFeesOwed(),
            MAX_PRECISION_DELTA,
            string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: iFIL convert to total assets invariant wrong"))
        );
        assertEq(
            pool.totalBorrowed(),
            totalBorrowedFromAccounts,
            string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: total borrowed invariant wrong"))
        );
    }

    // used in the agent police
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
}
