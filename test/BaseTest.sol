// SPDX-License-Identifier: UNLICENSED
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
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {RateModule} from "src/Pool/RateModule.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
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
import {Account} from "src/Types/Structs/Account.sol";
import {AgentBeneficiary, BeneficiaryHelpers} from "src/Types/Structs/Beneficiary.sol";
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

  uint256 public constant WAD = 1e18;
  // max FIL value - 2B atto
  uint256 public constant MAX_FIL = 2e27;
  uint256 public constant DUST = 10000;
  // 3 week window deadline for defaults
  uint256 public constant DEFAULT_WINDOW = EPOCHS_IN_WEEK * 3;
  uint256 public constant DEFAULT_BASE_RATE = 15e18;
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

    vcIssuer = vm.addr(vcIssuerPk);
    Deployer.setupContractRoutes(
      address(router),
      treasury,
      address(wFIL),
      address(new MinerRegistry(router)),
      address(new AgentFactory(router)),
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, DEFAULT_WINDOW, systemAdmin, router)),
      // 1e17 = 10% treasury fee on yield
      address(new PoolRegistry(IERC20(address(wFIL)), 1e17, 0, systemAdmin, router)),
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
    agent = Agent(payable(agentFactory.create(minerOwner, minerOwner)));
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
      amount,
      // no account yet (startEpoch)
      0
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
      principal,
      // no account yet (startEpoch)
      0
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
    uint256 principal,
    uint256 startEpoch
  ) internal pure returns (AgentData memory) {
    // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
    uint256 lockedFunds = collateralValue * 167 / 100;
    // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
    uint256 agentValue = lockedFunds * 120 / 100;
    return AgentData(
      agentValue,
      DEFAULT_BASE_RATE,
      collateralValue,
      // expectedDailyFaultPenalties
      0,
      expectedDailyRewards,
      gcred,
      lockedFunds,
      // qaPower hardcoded
      10e18,
      principal,
      startEpoch
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
    PoolToken liquidStakingToken = new PoolToken("Infinity Pool Staked FIL", "iFIL", systemAdmin);
    pool = IPool(new InfinityPool(
      systemAdmin,
      router,
      address(wFIL),
      address(new RateModule(systemAdmin, router, rateArray, levels)),
      // no min liquidity for test pool
      address(liquidStakingToken),
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
    uint256 gCredBasic,
    uint256 baseRate)
  {
    pool = createAndFundPool(stakeAmount, investor1);
    (agent, miner) = configureAgent(minerOwner);
    borrowCredBasic = issueGenericBorrowCred(agent.id(), borrowAmount);
    vcBasic = borrowCredBasic.vc;
    gCredBasic = vcBasic.getGCRED(credParser);
    baseRate = vcBasic.getBaseRate(credParser);
  }

  function createAccount(uint256 amount) internal returns(Account memory account) {
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
    vm.startPrank(_agentOperator(agent));
    // Establsh the state before the borrow
    StateSnapshot memory preBorrowState = _snapshot(address(agent), poolID);
    Account memory account = AccountHelpers.getAccount(router, address(agent), poolID);
    uint256 borrowBlock = block.number;
    agent.borrow(poolID, sc);

    vm.stopPrank();
    // Check the state after the borrow
    uint256 currentAgentBal = wFIL.balanceOf(address(agent));
    uint256 currentPoolBal = wFIL.balanceOf(address(GetRoute.pool(router, poolID)));
    assertEq(currentAgentBal, preBorrowState.agentBalanceWFIL + sc.vc.value);
    assertEq(currentPoolBal, preBorrowState.poolBalanceWFIL - sc.vc.value);

    account = AccountHelpers.getAccount(router, address(agent), poolID);

    // first time borrowing, check the startEpoch
    if (preBorrowState.agentBorrowed == 0) {
      assertEq(account.startEpoch, borrowBlock);
      assertEq(account.epochsPaid, borrowBlock);
    }

    assertEq(account.principal, preBorrowState.agentBorrowed + sc.vc.value);
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
    vm.startPrank(address(agent));
    vm.deal(address(agent), sc.vc.value);
    wFIL.deposit{value: sc.vc.value}();
    wFIL.approve(address(pool), sc.vc.value);
    vm.stopPrank();

    vm.startPrank(_agentOperator(agent));

    // Establsh the state before the borrow
    StateSnapshot memory preBorrowState = _snapshot(address(agent), pool.id());

    Account memory account = AccountHelpers.getAccount(
      router,
      address(agent),
      pool.id()
    );

    uint256 borrowBlock = block.number;
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

    assertTrue(agent.defaulted(), "Agent should be put into default");
  }

  function setAgentLiquidated(
    IAgent agent,
    uint256 rollFwdPeriod,
    uint256 borrowAmount,
    uint256 poolID
  ) internal {
    IAgentPolice police = GetRoute.agentPolice(router);

    setAgentDefaulted(
      agent,
      police.defaultWindow() + 1,
      1e18,
      poolID
    );

    vm.startPrank(IAuth(address(police)).owner());
    police.liquidatedAgent(address(agent));
    vm.stopPrank();

    assertTrue(police.liquidated(agent.id()), "Agent should be liquidated");
  }

  function configureBeneficiary(
    IAgent agent,
    address beneficiary,
    uint256 expiration,
    uint256 quota
  ) internal {
    changeBeneficiary(agent, beneficiary, expiration, quota);
    address prankster = makeAddr("PRANKSTER");

    // fuzz test accidentally sets beneficiary address to prankster
    if (beneficiary == prankster) {
      prankster = makeAddr("PRANKSTER2");
    }
    vm.startPrank(prankster);
    try GetRoute.agentPolice(router).approveAgentBeneficiary(agent.id()) {
      assertTrue(false, "Should not be able to approve beneficiary without permission");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), BeneficiaryHelpers.Unauthorized.selector);
    }
    vm.stopPrank();

    vm.startPrank(beneficiary);
    GetRoute.agentPolice(router).approveAgentBeneficiary(agent.id());
    vm.stopPrank();

    AgentBeneficiary memory ab = agent.beneficiary();

    assertEq(ab.proposed.beneficiary, address(0));
    assertEq(ab.proposed.expiration, 0);
    assertEq(ab.proposed.quota, 0);

    assertEq(ab.active.beneficiary, beneficiary);
    assertEq(ab.active.expiration, expiration);
    assertEq(ab.active.quota, quota);
  }

  function changeBeneficiary(
    IAgent agent,
    address beneficiary,
    uint256 expiration,
    uint256 quota
  ) internal {
    address prankster = makeAddr("PRANKSTER");
    vm.startPrank(prankster);
    try agent.changeBeneficiary(beneficiary, expiration, quota) {
      assertTrue(false, "Should not be able to change beneficiary without permission");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), Unauthorized.selector);
    }
    vm.stopPrank();
    vm.startPrank(_agentOwner(agent));
    agent.changeBeneficiary(beneficiary, expiration, quota);
    vm.stopPrank();

    AgentBeneficiary memory ab = agent.beneficiary();

    assertEq(ab.proposed.beneficiary, beneficiary);
    assertEq(ab.proposed.expiration, expiration);
    assertEq(ab.proposed.quota, quota);

    assertEq(ab.active.beneficiary, address(0));
    assertEq(ab.active.expiration, 0);
    assertEq(ab.active.quota, 0);
  }

  function _configureOffRamp(IPool pool) internal returns (IOffRamp ramp) {
    IPoolToken liquidStakingToken = pool.liquidStakingToken();
    PoolToken iou = new PoolToken("IOU", "IOU",systemAdmin);
    ramp = IOffRamp(new OffRamp(
      router,
      address(iou),
      address(pool.asset()),
      address(liquidStakingToken),
      systemAdmin,
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

  function _agentOwner(IAgent agent) internal view returns (address) {
    return IAuth(address(agent)).owner();
  }

  function _agentOperator(IAgent agent) internal view returns (address) {
    return IAuth(address(agent)).operator();
  }

  function _snapshot(address agent, uint256 poolID) internal view returns (StateSnapshot memory snapshot) {
    Account memory account = AccountHelpers.getAccount(router, agent, poolID);
    snapshot.agentBalanceWFIL = wFIL.balanceOf(agent);
    snapshot.poolBalanceWFIL = wFIL.balanceOf(address(GetRoute.pool(router, poolID)));
    snapshot.agentBorrowed = account.principal;
    snapshot.accountEpochsPaid = account.epochsPaid;
    snapshot.agentPoolBorrowCount = IAgent(agent).borrowedPoolsCount();
  }

  function _getAdjustedRate(uint256 gcred) internal view returns (uint256) {
    return rateArray[gcred] * DEFAULT_BASE_RATE / 1e18;
  }

  uint256[100] rateArray = [
    4414965412778580000 / EPOCHS_IN_YEAR,
    4349235141062740000 / EPOCHS_IN_YEAR,
    4284483465602120000 / EPOCHS_IN_YEAR,
    4220695816996550000 / EPOCHS_IN_YEAR,
    4157857842756010000 / EPOCHS_IN_YEAR,
    4095955404071180000 / EPOCHS_IN_YEAR,
    4034974572632200000 / EPOCHS_IN_YEAR,
    3974901627494750000 / EPOCHS_IN_YEAR,
    3915723051992720000 / EPOCHS_IN_YEAR,
    3857425530696970000 / EPOCHS_IN_YEAR,
    3799995946419270000 / EPOCHS_IN_YEAR,
    3743421377260860000 / EPOCHS_IN_YEAR,
    3687689093705020000 / EPOCHS_IN_YEAR,
    3632786555752810000 / EPOCHS_IN_YEAR,
    3578701410101580000 / EPOCHS_IN_YEAR,
    3525421487365380000 / EPOCHS_IN_YEAR,
    3472934799336830000 / EPOCHS_IN_YEAR,
    3421229536289670000 / EPOCHS_IN_YEAR,
    3370294064321610000 / EPOCHS_IN_YEAR,
    3320116922736550000 / EPOCHS_IN_YEAR,
    3270686821465950000 / EPOCHS_IN_YEAR,
    3221992638528500000 / EPOCHS_IN_YEAR,
    3174023417527600000 / EPOCHS_IN_YEAR,
    3126768365186160000 / EPOCHS_IN_YEAR,
    3080216848918030000 / EPOCHS_IN_YEAR,
    3034358394435680000 / EPOCHS_IN_YEAR,
    2989182683393360000 / EPOCHS_IN_YEAR,
    2944679551065520000 / EPOCHS_IN_YEAR,
    2900838984059630000 / EPOCHS_IN_YEAR,
    2857651118063160000 / EPOCHS_IN_YEAR,
    2815106235624060000 / EPOCHS_IN_YEAR,
    2773194763964300000 / EPOCHS_IN_YEAR,
    2731907272825930000 / EPOCHS_IN_YEAR,
    2691234472349260000 / EPOCHS_IN_YEAR,
    2651167210982610000 / EPOCHS_IN_YEAR,
    2611696473423120000 / EPOCHS_IN_YEAR,
    2572813378588330000 / EPOCHS_IN_YEAR,
    2534509177617850000 / EPOCHS_IN_YEAR,
    2496775251904890000 / EPOCHS_IN_YEAR,
    2459603111156950000 / EPOCHS_IN_YEAR,
    2422984391485550000 / EPOCHS_IN_YEAR,
    2386910853524280000 / EPOCHS_IN_YEAR,
    2351374380574900000 / EPOCHS_IN_YEAR,
    2316366976781090000 / EPOCHS_IN_YEAR,
    2281880765329300000 / EPOCHS_IN_YEAR,
    2247907986676470000 / EPOCHS_IN_YEAR,
    2214440996804070000 / EPOCHS_IN_YEAR,
    2181472265498200000 / EPOCHS_IN_YEAR,
    2148994374655220000 / EPOCHS_IN_YEAR,
    2117000016612670000 / EPOCHS_IN_YEAR,
    2085481992505030000 / EPOCHS_IN_YEAR,
    2054433210643890000 / EPOCHS_IN_YEAR,
    2023846684922350000 / EPOCHS_IN_YEAR,
    1993715533243080000 / EPOCHS_IN_YEAR,
    1964032975969850000 / EPOCHS_IN_YEAR,
    1934792334402030000 / EPOCHS_IN_YEAR,
    1905987029271920000 / EPOCHS_IN_YEAR,
    1877610579264340000 / EPOCHS_IN_YEAR,
    1849656599558330000 / EPOCHS_IN_YEAR,
    1822118800390510000 / EPOCHS_IN_YEAR,
    1794990985639900000 / EPOCHS_IN_YEAR,
    1768267051433740000 / EPOCHS_IN_YEAR,
    1741940984774080000 / EPOCHS_IN_YEAR,
    1716006862184860000 / EPOCHS_IN_YEAR,
    1690458848379090000 / EPOCHS_IN_YEAR,
    1665291194945890000 / EPOCHS_IN_YEAR,
    1640498239057040000 / EPOCHS_IN_YEAR,
    1616074402192890000 / EPOCHS_IN_YEAR,
    1592014188887100000 / EPOCHS_IN_YEAR,
    1568312185490170000 / EPOCHS_IN_YEAR,
    1544963058951340000 / EPOCHS_IN_YEAR,
    1521961555618630000 / EPOCHS_IN_YEAR,
    1499302500056770000 / EPOCHS_IN_YEAR,
    1476980793882640000 / EPOCHS_IN_YEAR,
    1454991414618200000 / EPOCHS_IN_YEAR,
    1433329414560340000 / EPOCHS_IN_YEAR,
    1411989919667660000 / EPOCHS_IN_YEAR,
    1390968128463780000 / EPOCHS_IN_YEAR,
    1370259310957000000 / EPOCHS_IN_YEAR,
    1349858807576000000 / EPOCHS_IN_YEAR,
    1329762028121470000 / EPOCHS_IN_YEAR,
    1309964450733250000 / EPOCHS_IN_YEAR,
    1290461620872890000 / EPOCHS_IN_YEAR,
    1271249150321400000 / EPOCHS_IN_YEAR,
    1252322716191860000 / EPOCHS_IN_YEAR,
    1233678059956740000 / EPOCHS_IN_YEAR,
    1215310986489730000 / EPOCHS_IN_YEAR,
    1197217363121810000 / EPOCHS_IN_YEAR,
    1179393118711390000 / EPOCHS_IN_YEAR,
    1161834242728280000 / EPOCHS_IN_YEAR,
    1144536784351310000 / EPOCHS_IN_YEAR,
    1127496851579380000 / EPOCHS_IN_YEAR,
    1110710610355710000 / EPOCHS_IN_YEAR,
    1094174283705210000 / EPOCHS_IN_YEAR,
    1077884150884630000 / EPOCHS_IN_YEAR,
    1061836546545360000 / EPOCHS_IN_YEAR,
    1046027859908720000 / EPOCHS_IN_YEAR,
    1030454533953520000 / EPOCHS_IN_YEAR,
    1015113064615720000 / EPOCHS_IN_YEAR,
    1000000000000000000 / EPOCHS_IN_YEAR
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
