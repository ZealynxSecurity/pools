// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Agent/Agent.sol";
import "src/Agent/AgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/IPool4626.sol";
import "src/Pool/PoolFactory.sol";
import "src/WFIL.sol";

import "./BaseTest.sol";

contract StatsTest is BaseTest {
  function testAssertTrue() public {
    assertTrue(true);
  }


    // function testIsLoanAgent() public {
    //     vm.startPrank(investor2);
    //     address la = agentFactory.create(address(miner));
    //     assertTrue(agentFactory.isAgent(la));
    //     assertFalse(agentFactory.isAgent(address(0xABC)));
    //     vm.stopPrank();
    // }


}
