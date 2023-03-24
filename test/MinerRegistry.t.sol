// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {AuthController} from "src/Auth/AuthController.sol";
import {errorSelector} from "./helpers/Utils.sol";
import "./BaseTest.sol";

contract MinerRegistryTest is BaseTest {
  using MinerHelper for uint64;

  IMinerRegistry public registry;
  address agentOwner = makeAddr("AGENT_OWNER");

  function setUp() public {
    registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
  }

  function testAddMiner() public {
    (Agent agent, uint64 miner) = configureAgent(agentOwner);
    assertTrue(registry.minerRegistered(agent.id(), miner), "Miner not registered");
  }

  function testRmMiner() public {
    (Agent agent, uint64 miner1) = configureAgent(agentOwner);
    uint64 miner2 = configureMiner(address(agent), agentOwner);

    address newOwner = makeAddr("NEW_OWNER");

    SignedCredential memory rmMinerCred = issueRemoveMinerCred(agent.id(), miner2);
    vm.startPrank(agentOwner);
    agent.removeMiner(newOwner, rmMinerCred);
    vm.stopPrank();
    assertTrue(registry.minerRegistered(agent.id(), miner1), "Miner 1 not removed");
    assertTrue(!registry.minerRegistered(agent.id(), miner2), "Miner 2 wrongly removed");
  }

  function testNonAgentAddMiner() public {
    try registry.addMiner(10) {
      assertTrue(false, "Should have reverted");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), AuthController.Unauthorized.selector, "Wrong error selector, expected unauthorized");
    }
  }

  function testNonAgentRmMiner() public {
    try registry.addMiner(1) {
      assertTrue(false, "Should have reverted");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), AuthController.Unauthorized.selector, "Wrong error selector, expected unauthorized");
    }
  }
}
