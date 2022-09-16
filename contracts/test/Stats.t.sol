// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
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
    //     address la = loanAgentFactory.create(address(miner));
    //     assertTrue(loanAgentFactory.isLoanAgent(la));
    //     assertFalse(loanAgentFactory.isLoanAgent(address(0xABC)));
    //     vm.stopPrank();
    // }


}
