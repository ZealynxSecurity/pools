// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Deployer} from "deploy/Deployer.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
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
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {MinerData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Stats} from "src/Stats/Stats.sol";
import "src/Constants/Routes.sol";

contract BasicRateModule is IRateModule {
  using FixedPointMathLib for uint256;
  uint256 rate;

  constructor(uint256 _rate) {
    rate = _rate;
  }

  function getRate(VerifiableCredential memory, uint256 amount) external view returns (uint256) {
    return amount.mulWadUp(rate);
  }
}

contract BaseTest is Test {
  address public constant ZERO_ADDRESS = address(0);
  address public treasury = makeAddr('TREASURY');
  address public router;

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
      address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, 1000)),
      address(new PoolFactory(wFIL)),
      address(new Stats()),
      address(new PowerToken()),
      vcIssuer
    );
    // any contract that extends RouterAware gets its router set here
    Deployer.setRouterOnContracts(address(router));
    // initialize the system's authentication system
    Deployer.initRoles(address(router), address(0));
  }

  function configureAgent(address minerOwner) public returns (Agent, MockMiner) {
    vm.startPrank(minerOwner);
    MockMiner miner = new MockMiner();

    // give miner some fake rewards and vest them over 1000 epochs
    vm.deal(address(miner), 100e18);
    miner.lockBalance(block.number, 1000, 100e18);
    vm.stopPrank();
    // create an agent for miner
    Agent agent = _configureAgent(minerOwner, miner);
    return (agent, miner);
  }

  function _configureAgent(address minerOwner, MockMiner miner) public returns (Agent) {
    address[] memory miners = new address[](1);
    miners[0] = address(miner);

    IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
    vm.startPrank(minerOwner);
    // create a agent for miner
    Agent agent = Agent(
      payable(
        agentFactory.create(address(0))
      ));
    // propose the change owner to the agent
    miner.change_owner_address(address(miner), address(agent));
    // confirm change owner address (agent1 now owns miner)
    agent.addMiners(miners);
    require(miner.get_owner(address(miner)) == address(agent), "Miner owner not set");
    require(agent.hasMiner(address(miner)), "Miner not registered");

    vm.stopPrank();
    return agent;
  }

  function issueGenericSC(
    address agent
  ) public returns (
    SignedCredential memory
  ) {
    uint256 qaPower = 10e18;

    MinerData memory miner = MinerData(
      1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
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
}
