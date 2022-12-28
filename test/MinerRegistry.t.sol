// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseTest.sol";

contract MinerRegistryTest is BaseTest {
  IMinerRegistry public registry;
  address agentOwner = makeAddr("AGENT_OWNER");
  address miner1 = makeAddr("MINER_1");
  address miner2 = makeAddr("MINER_2");
  address[] miners;

  function setUp() public {
    miners.push(miner1);
    miners.push(miner2);

    registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
  }

  function testAddMiner() public {
    (Agent agent, MockMiner miner) = configureAgent(agentOwner);
    assertTrue(registry.minerRegistered(agent.id(), address(miner)), "Miner not registered");
  }

  function testAddMiners() public {
    (Agent agent,) = configureAgent(agentOwner);
    vm.prank(address(agent));
    registry.addMiners(miners);
    assertTrue(registry.minerRegistered(agent.id(), address(miner1)), "Miner 1 not registered");
    assertTrue(registry.minerRegistered(agent.id(), address(miner2)), "Miner 2 not registered");
  }

  function testRmMiner() public {
    (Agent agent,) = configureAgent(agentOwner);
    vm.startPrank(address(agent));
    registry.addMiners(miners);
    registry.removeMiner(miner1);
    vm.stopPrank();
    assertTrue(!registry.minerRegistered(agent.id(), address(miner1)), "Miner 1 not removed");
    assertTrue(registry.minerRegistered(agent.id(), address(miner2)), "Miner 2 wrongly removed");
  }

  function testNonAgentAddMiner() public {
    vm.expectRevert("onlyAgent: Not authorized");
    registry.addMiner(miner1);
  }

  function testNonAgentAddMiners() public {
    vm.expectRevert("onlyAgent: Not authorized");
    registry.addMiner(miner1);
  }

  function testNonAgentRmMiners() public {
    vm.expectRevert("onlyAgent: Not authorized");
    registry.removeMiners(miners);
  }

  function testNonAgentRmMiner() public {
    vm.expectRevert("onlyAgent: Not authorized");
    registry.removeMiner(miner1);
  }
}
