// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.15;

// import "./BaseTest.sol";

// contract MinerRegistryTest is BaseTest {
//   using MinerHelper for uint64;

//   IMinerRegistry public registry;
//   address agentOwner = makeAddr("AGENT_OWNER");
//   address miner1 = makeAddr("MINER_1");
//   uint64 miner1Id = 10;
//   address miner2 = makeAddr("MINER_2");
//   uint64 miner2Id = 11;
//   uint64[] miners;

//   function setUp() public {
//     miners.push(miner1Id);
//     miners.push(miner2Id);

//     registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
//   }

//   function testAddMiner() public {
//     (Agent agent, uint64 miner) = configureAgent(agentOwner);
//     assertTrue(registry.minerRegistered(agent.id(), miner), "Miner not registered");
//   }

//   function testAddMiners() public {
//     (Agent agent,) = configureAgent(agentOwner);
//     vm.prank(address(agent));
//     registry.addMiners(miners);
//     assertTrue(registry.minerRegistered(agent.id(), miner1Id), "Miner 1 not registered");
//     assertTrue(registry.minerRegistered(agent.id(), miner2Id), "Miner 2 not registered");
//   }

//   function testRmMiner() public {
//     (Agent agent,) = configureAgent(agentOwner);
//     vm.startPrank(address(agent));
//     registry.addMiners(miners);
//     registry.removeMiner(miner1Id);
//     vm.stopPrank();
//     assertTrue(!registry.minerRegistered(agent.id(), miner1Id), "Miner 1 not removed");
//     assertTrue(registry.minerRegistered(agent.id(), miner2Id), "Miner 2 wrongly removed");
//   }

//   function testNonAgentAddMiner() public {
//     vm.expectRevert("onlyAgent: Not authorized");
//     registry.addMiner(miner1Id);
//   }

//   function testNonAgentAddMiners() public {
//     vm.expectRevert("onlyAgent: Not authorized");
//     registry.addMiner(miner1Id);
//   }

//   function testNonAgentRmMiners() public {
//     vm.expectRevert("onlyAgent: Not authorized");
//     registry.removeMiners(miners);
//   }

//   function testNonAgentRmMiner() public {
//     vm.expectRevert("onlyAgent: Not authorized");
//     registry.removeMiner(miner1Id);
//   }
// }
