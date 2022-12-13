// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Agent/Agent.sol";
import "src/Agent/AgentFactory.sol";
import "src/Agent/MinerRegistry.sol";
import "src/Auth/MultiRolesAuthority.sol";
import "src/Auth/Roles.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/PowerToken/PowerToken.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/Router/Router.sol";
import "src/Stats/Stats.sol";
import "src/VCVerifier/VCVerifier.sol";

/**
  This BaseTest contract sets up an environment equipped with:
  - AgentFactory
  - PoolFactory
  - WFIL
  - Stats
  - Credit scorer
  - Router
 */
contract BaseTest is Test {
  address public treasury = makeAddr('TREASURY');

  WFIL public wFIL;
  // This order matters when instantiating the router
  MinerRegistry registry;
  MultiRolesAuthority authority;
  AgentFactory public agentFactory;
  PoolFactory public poolFactory;
  VCVerifier public vcVerifier;
  Stats public stats;
  PowerToken public powToken;

  Router public router;

  // Should this name-space be changed to just glif.io?
  string constant public VERIFIED_NAME = "glif.io";
  string constant public VERIFIED_VERSION = "1";
  // MINER MANAGEMENT FUNCTIONS
  bytes4 public constant ADD_MINER_SELECTOR = bytes4(keccak256(bytes("addMiner(address)")));
  bytes4 public constant REMOVE_MINER_ADDR_SELECTOR = bytes4(keccak256(bytes("removeMiner(address)")));
  bytes4 public constant REMOVE_MINER_INDEX_SELECTOR = bytes4(keccak256(bytes("removeMiner(uint256)")));
  bytes4 public constant REVOKE_OWNERSHIP_SELECTOR = bytes4(keccak256(bytes("revokeOwnership(address,address)")));
  // FINANCIAL MANAMGEMENT FUNCTIONS
  bytes4 public constant WITHDRAW_SELECTOR = bytes4(keccak256(bytes("withdrawBalance(address)")));
  bytes4 public constant BORROW_SELECTOR = bytes4(keccak256(bytes("borrow(uint256,uint256)")));
  bytes4 public constant REPAY_SELECTOR = bytes4(keccak256(bytes("repay(uint256,uint256)")));

  constructor() {

    // TODO: this should be re-usable across tests and properly ordered
    wFIL = new WFIL();
    powToken = new PowerToken();
    registry = new MinerRegistry();
    authority = new MultiRolesAuthority(address(this), Authority(address(0)));
    agentFactory = new AgentFactory(VERIFIED_NAME, VERIFIED_VERSION);
    poolFactory = new PoolFactory(wFIL, treasury);
    vcVerifier = new VCVerifier("glif.io", "1");
    stats = new Stats();

    router = new Router(
      address(agentFactory),
      address(poolFactory),
      address(vcVerifier),
      address(stats),
      address(registry),
      address(authority),
      address(powToken)
    );

    agentFactory.setRouter(address(router));
    poolFactory.setRouter(address(router));
    vcVerifier.setRouter(address(router));
    stats.setRouter(address(router));
  }

  function setAgentPermissions(Agent agent, address manager) internal {
      MultiRolesAuthority agentAuthority = new MultiRolesAuthority(address(this), Authority(address(0)));
      agentAuthority.setUserRole(manager, Roles.AGENT_MINER_MANAGER, true);
      agentAuthority.setUserRole(manager, Roles.AGENT_FINANCE_MANAGER, true);
      agentAuthority.setRoleCapability(Roles.AGENT_MINER_MANAGER, ADD_MINER_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_MINER_MANAGER, REMOVE_MINER_INDEX_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_MINER_MANAGER, REMOVE_MINER_ADDR_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_MINER_MANAGER, REVOKE_OWNERSHIP_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_FINANCE_MANAGER, WITHDRAW_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_FINANCE_MANAGER, BORROW_SELECTOR, true);
      agentAuthority.setRoleCapability(Roles.AGENT_FINANCE_MANAGER, REPAY_SELECTOR, true);
      authority.setTargetCustomAuthority(address(agent), agentAuthority);
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
    vm.startPrank(minerOwner);

    // create a agent for miner
    Agent agent = Agent(
      payable(
        agentFactory.create()
      ));
    // propose the change owner to the agent
    miner.changeOwnerAddress(address(agent));
    vm.stopPrank();

    // Authority must be established by the main calling contract
    setAgentPermissions(agent, minerOwner);

    vm.startPrank(minerOwner);
    // confirm change owner address (agent1 now owns miner)
    agent.addMiner(address(miner));

    require(miner.currentOwner() == address(agent), "Miner owner not set");
    require(agent.hasMiner(address(miner)), "Miner not registered");

    vm.stopPrank();
    return agent;
  }
}
