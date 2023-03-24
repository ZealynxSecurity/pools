// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "test/helpers/MockMiner.sol";
import {GenesisPool} from "src/Pool/Genesis.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";
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
import {WFIL} from "shim/WFIL.sol";
import {PoolFactory} from "src/Pool/PoolFactory.sol";
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
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
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
import {EPOCHS_IN_WEEK, EPOCHS_IN_DAY,  EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

import "src/Constants/Routes.sol";

struct StateSnapshot {
    uint256 agentBalanceWFIL;
    uint256 poolBalanceWFIL;
    uint256 agentBorrowed;
}

contract BaseTest is Test {
  using MinerHelper for uint64;
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  // max FIL value - 2B atto
  uint256 public constant MAX_FIL = 2e27;
  uint256 public constant DUST = 10000;
  // 3 week window deadline for defaults
  uint256 public constant DEFAULT_WINDOW = EPOCHS_IN_WEEK * 3;
  uint256 public constant DEFAULT_BASE_RATE = 15e18;
  address public constant ZERO_ADDRESS = address(0);
  address public treasury = makeAddr('TREASURY');
  address public router;
  address public systemAdmin = makeAddr('SYSTEM_ADMIN');

  // just used for testing
  uint256 public vcIssuerPk = 1;
  address public vcIssuer;

  string constant public VERIFIED_NAME = "glif.io";
  string constant public VERIFIED_VERSION = "1";

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
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, DEFAULT_WINDOW, systemAdmin, systemAdmin, router)),
      // 1e17 = 10% treasury fee on yield
      address(new PoolFactory(IERC20(address(wFIL)), 1e17, 0, systemAdmin, systemAdmin, router)),
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

  function issueRemoveMinerCred(uint256 agent, uint64 miner) internal returns (SignedCredential memory) {
    // roll forward so we don't get an identical credential that's already been used
    vm.roll(block.number + 1);

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      1000,
      Agent.removeMiner.selector,
      miner,
      // agent data irrelevant for an remove miner cred
      bytes("")
    );

    return signCred(vc);
  }

  function issuePullFundsFromMinerCred(uint256 agent, uint64 miner, uint256 amount) internal returns (SignedCredential memory) {
    // roll forward so we don't get an identical credential that's already been used
    vm.roll(block.number + 1);

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      amount,
      Agent.pullFundsFromMiner.selector,
      miner,
      // agent data irrelevant for an pull funds from miner cred
      bytes("")
    );

    return signCred(vc);
  }

  function issuePushFundsToMinerCred(uint256 agent, uint64 miner, uint256 amount) internal returns (SignedCredential memory) {
    // roll forward so we don't get an identical credential that's already been used
    vm.roll(block.number + 1);

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      amount,
      Agent.pushFundsToMiner.selector,
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
      // agentValue => 2x the borrowAmount
      amount * 2,
      // good gcred score
      80,
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
    uint256 principle = amount * 2;
    uint256 gCred = 80;
    // NOTE: since we don't pull this off the pool it could be out of sync - careful
    uint256 adjustedRate = rateArray[gCred] * DEFAULT_BASE_RATE / 1e18;
    AgentData memory agentData = createAgentData(
      // agentValue => 2x the borrowAmount
      principle,
      // good gcred score
      gCred,
      // good EDR
      (adjustedRate * EPOCHS_IN_DAY * principle * 2) / 1e18,
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
      Agent.borrow.selector,
      // minerID irrelevant for borrow action
      0,
      abi.encode(agentData)
    );

    return signCred(vc);
  }

  function createAgentData(
    uint256 agentValue,
    uint256 gcred,
    uint256 expectedDailyRewards,
    uint256 principal,
    uint256 startEpoch
  ) internal pure returns (AgentData memory) {
    return AgentData(
      agentValue,
      DEFAULT_BASE_RATE,
      // collateralValue is 60% of agentValue
      agentValue * 60 / 100,
      // expectedDailyFaultPenalties
      0,
      expectedDailyRewards,
      gcred,
      // qaPower hardcoded
      10e18,
      principal,
      startEpoch
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
    IPoolFactory poolFactory = GetRoute.poolFactory(router);
    PoolToken liquidStakingToken = new PoolToken("LIQUID", "LQD",systemAdmin, systemAdmin);
    pool = IPool(new GenesisPool(
      systemAdmin,
      systemAdmin,
      router,
      address(wFIL),
      //
      address(new RateModule(systemAdmin, systemAdmin, router, rateArray)),
      // no min liquidity for test pool
      address(liquidStakingToken),
      0
    ));
    vm.prank(systemAdmin);
    liquidStakingToken.setMinter(address(pool));
    vm.startPrank(systemAdmin);
    poolFactory.attachPool(pool);
    vm.stopPrank();
  }

  function createAndFundPool(
    uint256 amount,
    address investor
  ) internal returns (IPool pool) {
    pool = createPool();
    depositFundsIntoPool(pool, amount, investor);
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
    StateSnapshot memory preBorrowState;

    preBorrowState.agentBalanceWFIL = wFIL.balanceOf(address(agent));
    Account memory account = AccountHelpers.getAccount(
      router,
      address(agent),
      poolID
    );

    preBorrowState.agentBorrowed = account.principal;

    uint256 borrowBlock = block.number;
    agent.borrow(poolID, sc);

    vm.stopPrank();
    // Check the state after the borrow
    uint256 currBalance = wFIL.balanceOf(address(agent));
    assertEq(currBalance, preBorrowState.agentBalanceWFIL + sc.vc.value);

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
    uint256 refund
  ) {
    vm.startPrank(_agentOperator(agent));

    // Establsh the state before the borrow
    StateSnapshot memory preBorrowState;
    preBorrowState.agentBalanceWFIL = wFIL.balanceOf(address(agent));
    preBorrowState.poolBalanceWFIL = wFIL.balanceOf(address(pool));
    Account memory account = AccountHelpers.getAccount(
      router,
      address(agent),
      pool.id()
    );

    preBorrowState.agentBorrowed = account.principal;

    uint256 borrowBlock = block.number;
    uint256 prePayEpochsPaid = account.epochsPaid;

    (
      rate,
      epochsPaid,
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

  function _configureOffRamp(IPool pool) internal returns (IOffRamp ramp) {
    IPoolToken liquidStakingToken = pool.liquidStakingToken();
    PoolToken iou = new PoolToken("IOU", "IOU",systemAdmin, systemAdmin);
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
}
