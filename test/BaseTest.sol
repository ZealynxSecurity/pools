// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "test/helpers/MockMiner.sol";
import {PreStake} from "test/helpers/PreStake.sol";
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
import {InfPoolSimpleRamp} from "src/OffRamp/SimpleRamp.sol";
import {RateModule} from "src/Pool/RateModule.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IInfinityPool} from "src/Types/Interfaces/IInfinityPool.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_WEEK, EPOCHS_IN_DAY,  EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
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

contract BaseTest is Test {
  using MinerHelper for uint64;
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;
  using FixedPointMathLib for uint256;

  uint256 public constant WAD = 1e18;
  // max FIL value - 2B atto
  uint256 public constant MAX_FIL = 2e27;
  uint256 public constant DUST = 10000;
  // 3 week window deadline for defaults
  uint256 public constant DEFAULT_WINDOW = EPOCHS_IN_WEEK * 3;
  uint256 public constant DEFAULT_BASE_RATE = 18e16;
  // by default, moderately good GCRED
  uint256 public constant GCRED = 80;
  address public constant ZERO_ADDRESS = address(0);
  address public treasury = makeAddr('TREASURY');
  address public router;
  address public systemAdmin = makeAddr('SYSTEM_ADMIN');

  // just used for testing
  uint256 public vcIssuerPk = 1;
  address public vcIssuer;

  string constant public VERIFIED_NAME = "glif.io";
  string constant public VERIFIED_VERSION = "1";
  uint256 MAX_UINT256 = type(uint256).max;

  WFIL wFIL = new WFIL(systemAdmin);
  MockIDAddrStore idStore;
  address credParser = address(new CredParser());
  constructor() {
    vm.startPrank(systemAdmin);
    // deploys the router
    router = address(new Router(systemAdmin));

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
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, DEFAULT_WINDOW, systemAdmin, systemAdmin, router, IPoolRegistry(poolRegistry), IWFIL(address(wFIL)))),
      poolRegistry,
      vcIssuer,
      credParser,
      address(new AgentDeployer())
    );
    // roll forward at least 1 window length so our computations dont overflow/underflow
    vm.roll(block.number + DEFAULT_WINDOW);

    // deploy an ID address store for mocking built-in miner actors
    idStore = new MockIDAddrStore();
    require(address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore");
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
    assertTrue(
      miner.isOwner(minerOwner),
      "The mock miner's current owner should be set to the original owner"
    );
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
    assertTrue(registry.minerRegistered(agent.id(), _miner), "After adding the miner the registry should have the miner's address as a registered miner");
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

  function issueWithdrawCred(uint256 agent, uint256 amount, AgentData memory agentData) internal returns (SignedCredential memory) {
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

  function issueRemoveMinerCred(
    uint256 agent,
    uint64 miner,
    AgentData memory agentData
  ) internal returns (SignedCredential memory) {
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

  function issuePullFundsCred(uint256 agent, uint64 miner, uint256 amount) internal returns (SignedCredential memory) {
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

  function issuePushFundsCred(uint256 agent, uint64 miner, uint256 amount) internal returns (SignedCredential memory) {
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

    AgentData memory agentData = createAgentData(
      // collateralValue => 2x the borrowAmount
      amount * 2,
      // good gcred score
      GCRED,
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

  function issueGenericRecoverCred(uint256 agent, uint256 faultySectors, uint256 liveSectors) internal returns (SignedCredential memory) {
    AgentData memory agentData = AgentData(
      0,
      0,
      0,
      0,
      0,
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

  function issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
    // roll forward so we don't get an identical credential that's already been used
    vm.roll(block.number + 1);
    uint256 principal = amount;
    // NOTE: since we don't pull this off the pool it could be out of sync - careful
    uint256 adjustedRate = _getAdjustedRate(GCRED);
    AgentData memory agentData = createAgentData(
      // collateralValue => 2x the borrowAmount
      amount * 2,
      // good gcred score
      GCRED,
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

  function createAgentData(
    uint256 collateralValue,
    uint256 gcred,
    uint256 expectedDailyRewards,
    uint256 principal
  ) internal pure returns (AgentData memory) {
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
      gcred,
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
    return AgentData(
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0
    );
  }

  function signCred(
    VerifiableCredential memory vc
  ) public returns (
    SignedCredential memory
  ) {
    bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
    return SignedCredential(vc, v, r, s);
  }

  function createPool() internal returns (IPool pool) {
    IPoolRegistry poolRegistry = GetRoute.poolRegistry(router);
    PoolToken liquidStakingToken = new PoolToken(systemAdmin);
    pool = IPool(new InfinityPool(
      systemAdmin,
      router,
      address(wFIL),
      address(new RateModule(systemAdmin, router, rateArray, levels)),
      // no min liquidity for test pool
      address(liquidStakingToken),
      address(new PreStake(systemAdmin, IWFIL(address(wFIL)), IPoolToken(address(liquidStakingToken)))),
      0,
      GetRoute.poolRegistry(router).allPoolsLength()
    ));
    vm.prank(systemAdmin);
    liquidStakingToken.setMinter(address(pool));
    vm.startPrank(systemAdmin);
    poolRegistry.attachPool(pool);
    vm.stopPrank();
  }

  function createAndFundPool(
    uint256 amount,
    address investor
  ) internal returns (IPool pool) {
    pool = createPool();
    depositFundsIntoPool(pool, amount, investor);
  }

  function PoolBasicSetup(
    uint256 stakeAmount,
    uint256 borrowAmount,
    address investor1,
    address minerOwner
  ) internal returns (
    IPool pool,
    Agent agent,
    uint64 miner,
    SignedCredential memory borrowCredBasic,
    VerifiableCredential memory vcBasic,
    uint256 gCredBasic
  ) {
    pool = createAndFundPool(stakeAmount, investor1);
    (agent, miner) = configureAgent(minerOwner);
    borrowCredBasic = issueGenericBorrowCred(agent.id(), borrowAmount);
    vcBasic = borrowCredBasic.vc;
    gCredBasic = vcBasic.getGCRED(credParser);
  }

  function createAccount(uint256 amount) internal view returns(Account memory account) {
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

  function agentBorrow(
    IAgent agent,
    uint256 poolID,
    SignedCredential memory sc
  ) internal {
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
      assertEq(account.principal, preBorrowState.agentBorrowed + sc.vc.value, "Account principal should be correct");
      assertEq(pool.getAgentBorrowed(agent.id()) - preBorrowState.agentBorrowed, currentAgentBal - preBorrowState.agentBalanceWFIL, "Pool agentBorrowed should increase by the right amount");
      assertEq(pool.totalBorrowed(), preTotalBorrowed + currentAgentBal - preBorrowState.agentBalanceWFIL, "Pool totalBorrowed should be correct");
    }
    testInvariants(pool, "agentBorrow End");
  }

  function agentPay(
    IAgent agent,
    IPool pool,
    SignedCredential memory sc
  ) internal returns (
    uint256 rate,
    uint256 epochsPaid,
    uint256 principalPaid,
    uint256 refund,
    StateSnapshot memory prePayState
  ) {
    testInvariants(pool, "agentPay Start");
    vm.startPrank(address(agent));
    vm.deal(address(agent), sc.vc.value);
    wFIL.deposit{value: sc.vc.value}();
    wFIL.approve(address(pool), sc.vc.value);
    vm.stopPrank();

    vm.startPrank(_agentOperator(agent));

    Account memory account = AccountHelpers.getAccount(
      router,
      address(agent),
      pool.id()
    );

    uint256 prePayEpochsPaid = account.epochsPaid;

    prePayState = _snapshot(address(agent), pool.id());

    (
      rate,
      epochsPaid,
      principalPaid,
      refund
    ) = agent.pay(pool.id(), sc);

    vm.stopPrank();

    account = AccountHelpers.getAccount(
      router,
      address(agent),
      pool.id()
    );

    assertGt(rate, 0, "Should not have a 0 rate");

    // there is an unlikely case where these tests fail when the amount paid is _exactly_ the amount needed to exit - meaning refund is 0
    if (refund > 0) {
      assertEq(account.epochsPaid, 0, "Should have 0 epochs paid if there was a refund - meaning all principal was paid");
      assertEq(account.principal, 0, "Should have 0 principal if there was a refund - meaning all principal was paid");
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

  function calculateInterestOwed(
    IPool pool,
    VerifiableCredential memory vc,
    uint256 borrowAmount,
    uint256 rollFwdAmt
  ) internal view returns (
    uint256 interestOwed,
    uint256 interestOwedPerEpoch
  ) {
    // since gcred is hardcoded in the credential, we know the rate ahead of time (rate does not change if gcred does not change, even if other financial statistics change)
    // rate here is WAD based
    uint256 rate = pool.getRate(vc);
    // note we add 1 more bock of interest owed to account for the roll forward of 1 epoch inside agentBorrow helper
    // since borrowAmount is also WAD based, the _interestOwedPerEpoch is also WAD based (e18 * e18 / e18)
    uint256 _interestOwedPerEpoch = borrowAmount.mulWadUp(rate);
    // _interestOwedPerEpoch is mulWadUp by epochs (not WAD based), which cancels the WAD out for interestOwed
    interestOwed = (_interestOwedPerEpoch.mulWadUp(rollFwdAmt + 1));
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

  function setAgentDefaulted(
    IAgent agent,
    uint256 rollFwdPeriod,
    uint256 borrowAmount,
    uint256 poolID
  ) internal {
    IAgentPolice police = GetRoute.agentPolice(router);
    SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

    agentBorrow(agent, poolID, borrowCred);

    vm.roll(block.number + rollFwdPeriod);

    vm.startPrank(IAuth(address(police)).owner());
    police.setAgentDefaulted(address(agent));
    vm.stopPrank();

    IPool pool = GetRoute.pool(GetRoute.poolRegistry(router), poolID);
    testInvariants(pool, "setAgentDefaulted");

    assertTrue(agent.defaulted(), "Agent should be put into default");
  }

  function _configureOffRamp(IPool pool) internal returns (IOffRamp ramp) {
    IPoolToken liquidStakingToken = pool.liquidStakingToken();
    PoolToken iou = new PoolToken(systemAdmin);
    ramp = IOffRamp(new InfPoolSimpleRamp(
      router,
      pool.id()
    ));
    vm.startPrank(systemAdmin);
    iou.setMinter(address(ramp));
    iou.setBurner(address(ramp));
    liquidStakingToken.setBurner(address(ramp));
    vm.stopPrank();

    vm.prank(IAuth(address(pool)).owner());
    pool.setRamp(ramp);
  }

  function _bumpMaxEpochsOwedTolerance(uint256 epochs, address pool) internal {
    vm.startPrank((IAuth(pool)).owner());
    // temporarily up the buffer of the pool and agent police to get past the epochs paid borrow buffer so we can borrow the rest
    IInfinityPool(pool).setMaxEpochsOwedTolerance(epochs);
    IAgentPolice(GetRoute.agentPolice(router)).setMaxEpochsOwedTolerance(epochs);
    vm.stopPrank();
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

  function _getAdjustedRate(uint256 gcred) internal view returns (uint256) {
    return DEFAULT_BASE_RATE.mulWadUp(rateArray[gcred - 40]);
  }

  function testInvariants(IPool pool, string memory label) internal {
    _invIFILWorthAssetsOfPool(pool, label);
  }

  function _invIFILWorthAssetsOfPool(IPool pool, string memory label) internal {
    // this invariant knows that iFIL should represent the total value of the pool, which is composed of:
    // 1. all funds given to miners + agents
    // 2. balance of wfil held by the pool
    // 3. minus any fees held temporarily by the pool
    uint256 agentCount = GetRoute.agentFactory(router).agentCount();

    uint256 totalBorrowedFromAccounts = 0;

    for (uint256 i = 1; i <= agentCount; i++) {
      Account memory account = AccountHelpers.getAccount(router, i, pool.id());
      // the invariant breaks when an account is in default, we no longer expect to get that amount back
      if (!account.defaulted) {
        totalBorrowedFromAccounts += pool.getAgentBorrowed(i);
      }
    }

    uint256 poolAssets = wFIL.balanceOf(address(pool)) - pool.feesCollected();

    // if we take the total supply of iFIL and convert it to assets, we should get the total pools assets + lent out funds
    uint256 totalIFILSupply = pool.liquidStakingToken().totalSupply();

    assertEq(poolAssets + totalBorrowedFromAccounts, pool.totalAssets(), label);
    assertEq(pool.convertToAssets(totalIFILSupply), poolAssets + totalBorrowedFromAccounts, label);
    assertEq(pool.totalBorrowed(), totalBorrowedFromAccounts, label);
  }

  uint256[61] rateArray = [
    2113986132250972433409436834094 ,
    2087561305597835277777777777777 ,
    2061136478944698122146118721461 ,
    2034711652291560966514459665144 ,
    2008286825638423811834094368340 ,
    1981861998985286656202435312024 ,
    1955437172332149500570776255707 ,
    1929012345679012344939117199391 ,
    1902587519025875190258751902587 ,
    1876162692372738034627092846270 ,
    1796888212413326567732115677321 ,
    1770463385760189413051750380517 ,
    1744038559107052257420091324200 ,
    1717613732453915101788432267884 ,
    1691188905800777946156773211567 ,
    1664764079147640791476407914764 ,
    1638339252494503635844748858447 ,
    1611914425841366480213089802130 ,
    1585489599188229324581430745814 ,
    1559064772535092168949771689497 ,
    1532639945881955014269406392694 ,
    1511500084559445289193302891933 ,
    1490360223236935565068493150684 ,
    1469220361914425840943683409436 ,
    1448080500591916116818873668188 ,
    1426940639269406392694063926940 ,
    1405800777946896667617960426179 ,
    1384660916624386943493150684931 ,
    1363521055301877219368340943683 ,
    1342381193979367495243531202435 ,
    1321241332656857770167427701674 ,
    1305386436664975477549467275494 ,
    1289531540673093183980213089802 ,
    1273676644681210890410958904109 ,
    1257821748689328597792998477929 ,
    1241966852697446304223744292237 ,
    1226111956705564010654490106544 ,
    1210257060713681718036529680365 ,
    1194402164721799424467275494672 ,
    1178547268729917130898021308980 ,
    1162692372738034838280060882800 ,
    1152122442076779976217656012176 ,
    1141552511415525114155251141552 ,
    1130982580754270251141552511415 ,
    1120412650093015389079147640791 ,
    1056993066125486216704718417047 ,
    1099272788770505664954337899543 ,
    1088702858109250802891933028919 ,
    1078132927447995940829528158295 ,
    1067562996786741078767123287671 ,
    1056993066125486216704718417047 ,
    1046423135464231354642313546423 ,
    1035853204802976491628614916286 ,
    1025283274141721629566210045662 ,
    1014713343480466767503805175038 ,
    1004143412819211905441400304414 ,
    993573482157957043378995433789 ,
    983003551496702181316590563165 ,
    972433620835447319254185692541 ,
    961863690174192457191780821917 ,
    951293759512937595129375951293
  ];

  // used in the rate module
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
