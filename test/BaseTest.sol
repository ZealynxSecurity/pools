// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Deployer} from "deploy/Deployer.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
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
import {MinerData, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
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
      makeAddr('TREASURY_ADMIN')
    );
    vcIssuer = vm.addr(vcIssuerPk);
    Deployer.setupContractRoutes(
      address(router),
      treasury,
      address(wFIL),
      address(new MinerRegistry()),
      address(new AgentFactory(VERIFIED_NAME, VERIFIED_VERSION)),
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
    IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
    vm.startPrank(minerOwner);
    // create a agent for miner
    Agent agent = Agent(
      payable(
        agentFactory.create(address(0))
      ));
    // propose the change owner to the agent
    miner.changeOwnerAddress(address(agent));
    // confirm change owner address (agent1 now owns miner)
    agent.addMiner(address(miner));
    require(miner.currentOwner() == address(agent), "Miner owner not set");
    require(agent.hasMiner(address(miner)), "Miner not registered");

    vm.stopPrank();
    return agent;
  }

  function issueGenericVC(
    address agent
  ) public returns (
    VerifiableCredential memory vc,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) {
    uint256 qaPower = 10e18;

    MinerData memory miner = MinerData(
      1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, qaPower, 5e18, 0, 0
    );

    vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      miner
    );

    (v, r, s) = issueVC(vc);
  }

  function issueVC(
    VerifiableCredential memory vc
  ) public returns (
    uint8 v,
    bytes32 r,
    bytes32 s
  ) {
    bytes32 digest = IVCVerifier(vc.subject).digest(vc);
    (v, r, s) = vm.sign(vcIssuerPk, digest);
  }
}
