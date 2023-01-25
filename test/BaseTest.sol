// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/MockMiner.sol";
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
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {MinerData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {MockPoolImplementation} from "test/helpers/MockPoolImplementation.sol";
import "src/Constants/Routes.sol";

contract BaseTest is Test {
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

  constructor() {
    // deploys the coreAuthority and the router
    (router, coreAuthority) = Deployer.init();
    // these two route setting calls are separate because they blow out the call stack if they're one func
    Deployer.setupAdminRoutes(
      address(router),
      makeAddr('ROUTER_ADMIN'),
      makeAddr('AGENT_FACTORY_ADMIN'),
      makeAddr('POWER_TOKEN_ADMIN'),
      makeAddr('MINER_REGISTRY_ADMIN'),
      makeAddr('POOL_FACTORY_ADMIN'),
      msg.sender,
      makeAddr('TREASURY_ADMIN'),
      makeAddr('AGENT_POLICE_ADMIN')
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
      address(new PoolFactory(wFIL, 1e17, 0)),
      address(new PowerToken()),
      vcIssuer
    );
    // any contract that extends RouterAware gets its router set here
    Deployer.setRouterOnContracts(address(router));
    // initialize the system's authentication system
    Deployer.initRoles(address(router), address(0));
    // roll forward at least 1 window length so our computations dont overflow/underflow
    vm.roll(block.number + WINDOW_LENGTH);
  }

  function configureAgent(address minerOwner) public returns (Agent, MockMiner) {
    MockMiner miner = MockMiner(payable(_newMiner(minerOwner)));

    // give miner some fake rewards and vest them over 1000 epochs
    vm.deal(address(miner), 100e18);
    vm.prank(minerOwner);
    miner.lockBalance(block.number, 1000, 100e18);
    // create an agent for miner
    Agent agent = _configureAgent(minerOwner, miner);
    return (agent, miner);
  }

  function _configureAgent(address minerOwner, MockMiner miner) public returns (Agent) {
    IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
    // create a agent for miner
    vm.prank(minerOwner);
    Agent agent = Agent(
      payable(
        agentFactory.create(address(0))
      ));

    _agentClaimOwnership(address(agent), address(miner), minerOwner);
    return agent;
  }

  function _newMiner(address minerOwner) internal returns (address) {
    vm.prank(minerOwner);
    return address(new MockMiner());
  }

  function _agentClaimOwnership(address _agent, address _miner, address _minerOwner) internal {
    IAgent agent = IAgent(_agent);
    IMockMiner miner = IMockMiner(_miner);
    address[] memory miners = new address[](1);
    miners[0] = _miner;
    vm.startPrank(_minerOwner);
    miner.change_owner_address(_miner, _agent);
    // confirm change owner address (agent1 now owns miner)
    agent.addMiners(miners);
    require(miner.get_owner(_miner) == _agent, "Miner owner not set");
    require(agent.hasMiner(_miner), "Miner not registered");
    vm.stopPrank();
  }

  function createCustomCredential(
      address agent,
      uint256 qaPower,
      uint256 expectedDailyRewards,
      uint256 assets,
      uint256 liabilities
    ) internal view returns (VerifiableCredential memory vc) {
      MinerData memory _miner = MinerData(
          assets, expectedDailyRewards, 0, 0.5e18, liabilities, 10e18, 10, qaPower, 5e18, 0, 0
      );

      vc = VerifiableCredential(
          vcIssuer,
          address(agent),
          block.number,
          block.number + 100,
          1000,
          _miner
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

    MinerData memory miner = MinerData(
      assets, expectedDailyRewards, 0, 0.5e18, liabilities, 10e18, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      expectedDailyRewards * 5,
      miner
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
    return pool;
  }
}
