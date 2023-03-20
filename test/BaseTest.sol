// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "test/helpers/MockMiner.sol";
import {GenesisPool} from "src/Pool/Genesis.sol";
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
import {WFIL} from "src/WFIL.sol";
import {PoolFactory} from "src/Pool/PoolFactory.sol";
import {Router} from "src/Router/Router.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {MinerHelper} from "helpers/MinerHelper.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_WEEK} from "src/Constants/Epochs.sol";

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
  // 3 week window deadline for defaults
  uint256 public constant DEFAULT_WINDOW = EPOCHS_IN_WEEK * 3;
  address public constant ZERO_ADDRESS = address(0);
  address public treasury = makeAddr('TREASURY');
  address public router;
  address public systemAdmin = makeAddr('SYSTEM_ADMIN');

  // just used for testing
  uint256 public vcIssuerPk = 1;
  address public vcIssuer;

  string constant public VERIFIED_NAME = "glif.io";
  string constant public VERIFIED_VERSION = "1";

  WFIL wFIL = new WFIL();
  MockIDAddrStore idStore;

  constructor() {
    vm.startPrank(systemAdmin);
    // deploys the router
    router = address(new Router(systemAdmin));

    vcIssuer = vm.addr(vcIssuerPk);
    Deployer.setupContractRoutes(
      address(router),
      treasury,
      address(wFIL),
      address(new MinerRegistry()),
      address(new AgentFactory()),
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, DEFAULT_WINDOW, systemAdmin, systemAdmin)),
      // 1e17 = 10% treasury fee on yield
      address(new PoolFactory(IERC20(address(wFIL)), 1e17, 0, systemAdmin, systemAdmin)),
      vcIssuer,
      address(new CredParser()),
      address(new AgentDeployer())
    );
    // any contract that extends RouterAware gets its router set here
    Deployer.setRouterOnContracts(address(router));
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

  function issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
    // roll forward so we don't get an identical credential that's already been used
    vm.roll(block.number + 1);

    AgentData memory agentData = createAgentData(
      // agentValue => 2x the borrowAmount
      amount * 2,
      // good gcred score
      80,
      // good EDR
      1000,
      // no principal
      0,
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
      15e16,
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

    pool = IPool(new GenesisPool(
      systemAdmin,
      systemAdmin,
      router,
      address(wFIL),
      //
      address(0),
      // no min liquidity for test pool
      0,
      15e16
    ));
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

  function _configureOffRamp(IPool pool) internal returns (IOffRamp ramp) {
    ramp = IOffRamp(new OffRamp(
      router,
      address(pool.exitToken()),
      address(pool.asset()),
      systemAdmin,
      pool.id()
    ));

    vm.prank(IAuth(address(pool)).owner());
    pool.setRamp(ramp);
  }

  function _agentOwner(IAgent agent) internal view returns (address) {
    return IAuth(address(agent)).owner();
  }

  function _agentOperator(IAgent agent) internal view returns (address) {
    return IAuth(address(agent)).operator();
  }
}
