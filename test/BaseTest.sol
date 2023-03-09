// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "test/helpers/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Deployer} from "deploy/Deployer.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {WFIL} from "src/WFIL.sol";
import {PowerToken} from "src/PowerToken/PowerToken.sol";
import {PoolFactory} from "src/Pool/PoolFactory.sol";
import {Router} from "src/Router/Router.sol";
import {OffRamp} from "src/OffRamp/OffRamp.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {MockPoolImplementation} from "test/helpers/MockPoolImplementation.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {MinerHelper} from "helpers/MinerHelper.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";

import "src/Constants/Routes.sol";

struct StateSnapshot {
    uint256 balanceWFIL;
    uint256 poolBalanceWFIL;
    uint256 powerStake;
    uint256 borrowed;
    uint256 powerBalance;
    uint256 powerBalancePool;
}

contract BaseTest is Test {
  using MinerHelper for uint64;
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  uint256 public constant WINDOW_LENGTH = 1000;
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
  IMultiRolesAuthority coreAuthority;
  MockIDAddrStore idStore;

  constructor() {
    vm.startPrank(systemAdmin);
    // deploys the coreAuthority and the router
    (router, coreAuthority) = Deployer.init(systemAdmin);
    // these two route setting calls are separate because they blow out the call stack if they're one func
    Deployer.setupAdminRoutes(
      router,
      systemAdmin,
      systemAdmin,
      systemAdmin,
      systemAdmin,
      systemAdmin,
      systemAdmin,
      systemAdmin,
      systemAdmin
    );
    vcIssuer = vm.addr(vcIssuerPk);
    Deployer.setupContractRoutes(
      address(router),
      treasury,
      address(wFIL),
      address(new MinerRegistry()),
      address(new AgentFactory()),
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, WINDOW_LENGTH)),
      // 1e17 = 10% treasury fee on yield
      address(new PoolFactory(IERC20(address(wFIL)), 1e17, 0)),
      address(new PowerToken()),
      vcIssuer,
      address(new CredParser())
    );
    // any contract that extends RouterAware gets its router set here
    Deployer.setRouterOnContracts(address(router));
    // initialize the system's authentication system
    Deployer.initRoles(address(router), systemAdmin);
    // roll forward at least 1 window length so our computations dont overflow/underflow
    vm.roll(block.number + WINDOW_LENGTH);

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
    agent = Agent(payable(agentFactory.create(address(0))));
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

  function pushWFILFunds(address target, uint256 amount, address sender) public {
    vm.deal(sender, amount);
    vm.startPrank(sender);
    uint256 startingBalance = wFIL.balanceOf(address(target));
    // give the agent some funds to push
    wFIL.deposit{value: amount}();
    wFIL.transfer(address(target), amount);


    assertEq(wFIL.balanceOf(address(target)), startingBalance + amount);
    vm.stopPrank();
  }

  function _agentClaimOwnership(address _agent, uint64 _miner, address _minerOwner) internal {
    IMinerRegistry registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
    IAgent agent = IAgent(_agent);

    uint64[] memory miners = new uint64[](1);
    miners[0] = _miner;
    vm.startPrank(_minerOwner);
    _miner.changeOwnerAddress(address(_agent));
    vm.stopPrank();

    // confirm change owner address (agent now owns miner)
    vm.startPrank(address(agent));
    agent.addMiners(miners);
    require(agent.hasMiner(_miner), "Miner not registered");
    assertTrue(_miner.isOwner(_agent), "The mock miner's owner should change to the agent");
    assertTrue(agent.hasMiner(_miner), "The miner should be registered as a miner on the agent");
    assertTrue(registry.minerRegistered(agent.id(), _miner), "After adding the miner the registry should have the miner's address as a registered miner");
    vm.stopPrank();
  }

  function createCustomCredential(
      address agent,
      uint256 qaPower,
      uint256 expectedDailyRewards,
      uint256 assets,
      uint256 liabilities
    ) internal view returns (VerifiableCredential memory vc) {
      AgentData memory _miner = AgentData(
          assets, expectedDailyRewards, 0, 0.5e18, liabilities, 10e18, 10, qaPower, 5e18, 0, 0
      );

      vc = VerifiableCredential(
          vcIssuer,
          address(agent),
          block.number,
          block.number + 100,
          1000,
          abi.encode(_miner)
      );
  }

  function issueGenericSC(
    address agent
  ) public returns (
    SignedCredential memory
  ) {
    uint256 qaPower = 10e18;
    uint256 expectedDailyRewards = 20e18;
    uint256 assets = 10e18;
    uint256 liabilities = 2e18;

    AgentData memory miner = AgentData(
      assets, expectedDailyRewards, 0, 0.5e18, liabilities, 10e18, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      expectedDailyRewards * 5,
      abi.encode(miner)
    );

    return issueSC(vc);
  }

  function issueSC(
    VerifiableCredential memory vc
  ) public returns (
    SignedCredential memory
  ) {
    bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
    return SignedCredential(vc, v, r, s);
  }

  function createPool(
    string memory poolName,
    string memory poolSymbol,
    address poolOperator,
    uint256 fee
    ) internal returns(IPool)
  {
    address poolFactoryAdmin = IRouter(router).getRoute(ROUTE_POOL_FACTORY_ADMIN);
    vm.startPrank(poolFactoryAdmin);

    IPoolFactory poolFactory = GetRoute.poolFactory(router);

    PoolTemplate template = new PoolTemplate();
    MockPoolImplementation broker = new MockPoolImplementation(fee, router);

    template.setRouter(router);
    poolFactory.approveTemplate(address(template));
    poolFactory.approveImplementation(address(broker));

    IPool pool = poolFactory.createPool(
        poolName,
        poolSymbol,
        poolOperator,
        address(broker),
        address(template)
    );
    vm.stopPrank();

    _configureOffRamp(pool);

    return pool;
  }

  function mintAndApprovePower(IAgent _agent, address _pool, address _powerToken, uint256 amount, SignedCredential memory signedCred) internal {
    vm.startPrank(address(_agent));
    _agent.mintPower(amount, signedCred);
    IERC20(_powerToken).approve(_pool, amount);
    vm.stopPrank();
  }

  function createAndPrimePool(
    string memory poolName,
    string memory poolSymbol,
    address poolOperator,
    uint256 fee,
    uint256 _amount,
    address investor
    ) internal returns(IPool)
  {
    IPool pool = createPool(poolName, poolSymbol, poolOperator, fee);
    primePool(pool, _amount, investor);
    return pool;
  }

  function primePool(IPool pool, uint256 _amount, address investor) internal {
    IERC4626 pool4626 = IERC4626(address(pool));
    // investor1 stakes 10 FIL
    vm.deal(investor, _amount);
    vm.startPrank(investor);
    wFIL.deposit{value: _amount}();
    wFIL.approve(address(pool), _amount);
    pool4626.deposit(_amount, investor);
    vm.stopPrank();
  }

    function agentMintAndApprovePower(address pool, address _powerToken, IAgent _agent, SignedCredential memory _signedCred, uint256 _amount) internal {
        vm.startPrank(address(_agent));
        _agent.mintPower(_amount, _signedCred);
        IERC20(_powerToken).approve(pool, _amount);
        vm.stopPrank();
    }

    function agentBorrow(IAgent _agent, uint256 _borrowAmount, SignedCredential memory _signedCred, IPool _pool, address _powerToken, uint256 powerStake) internal {
        vm.startPrank(address(_agent));
        // Establsh the state before the borrow
        StateSnapshot memory preBorrowState;
        preBorrowState.balanceWFIL = wFIL.balanceOf(address(_agent));
        Account memory account = AccountHelpers.getAccount(router, address(_agent), _pool.id());
        preBorrowState.powerStake = account.powerTokensStaked;
        preBorrowState.borrowed = account.totalBorrowed;
        preBorrowState.powerBalance = IERC20(_powerToken).balanceOf(address(_agent));
        preBorrowState.powerBalancePool = IERC20(_powerToken).balanceOf(address(_pool));

        _agent.borrow(_borrowAmount, 0, _signedCred, powerStake);
        vm.stopPrank();

        // Check the state after the borrow
        uint256 currBalance = wFIL.balanceOf(address(_agent));
        assertEq(currBalance, preBorrowState.balanceWFIL + _borrowAmount);

        account = AccountHelpers.getAccount(router, address(_agent), _pool.id());
        assertEq(account.startEpoch, block.number);
        assertGt(account.pmtPerEpoch(), 0);

        uint256 rate = _pool.implementation().getRate(
            _borrowAmount,
            powerStake,
            GetRoute.agentPolice(router).windowLength(),
            account,
            _signedCred.vc
        );
        assertEq(account.perEpochRate, rate);
        assertEq(account.powerTokensStaked, preBorrowState.powerStake + powerStake);
        assertEq(account.totalBorrowed, preBorrowState.borrowed + _borrowAmount);

        assertEq(
            IERC20(_powerToken).balanceOf(address(_agent)),
            preBorrowState.powerBalance - powerStake
        );

        assertEq(
            IERC20(_powerToken).balanceOf(address(_pool)),
            preBorrowState.powerBalancePool + powerStake
        );
    }

  function _configureOffRamp(IPool pool) internal returns (IOffRamp ramp) {
    ramp = IOffRamp(new OffRamp(
      router,
      address(pool.iou()),
      address(pool.asset()),
      pool.id()
    ));

    vm.prank(address(GetRoute.poolFactory(router)));
    pool.setRamp(ramp);
  }
}
