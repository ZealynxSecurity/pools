// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import 'src/Miner/MockMiner.sol';

contract LoanAgentTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);

    MockMiner miner;
    LoanAgentFactory loanAgentFactory;
    function setUp() public {
        loanAgentFactory = new LoanAgentFactory();
        miner = new MockMiner();
        miner.changeOwnerAddress(alice);
        vm.prank(alice);
        miner.changeOwnerAddress(alice);
        require(miner.currentOwner() == alice);
    }

    function testInitialState() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(loanAgentFactory.create(address(miner)));

        assertEq(loanAgent.miner(), address(miner));
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent));
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner));
        assertEq(miner.currentOwner(), alice);
        assertEq(loanAgent.owner(), address(0));

        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        vm.stopPrank();

        assertEq(loanAgent.miner(), address(miner));
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent));
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner));
        assertEq(miner.currentOwner(), address(loanAgent));
        assertEq(loanAgent.owner(), alice);
    }

    function testFailClaimOwnership() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(loanAgentFactory.create(address(miner)));
        miner.changeOwnerAddress(address(loanAgent));
        vm.stopPrank();

        vm.prank(bob);
        loanAgent.claimOwnership();
    }

    function testDuplicateLoanAgents() public {
        address loanAgentAddr = loanAgentFactory.create(address(miner));
        address loanAgentAddr2 = loanAgentFactory.create(address(miner));

        assertEq(loanAgentAddr, loanAgentAddr2);
    }

    function testRevokeOwnership() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(loanAgentFactory.create(address(miner)));
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();

        loanAgent.revokeMinerOwnership(bob);

        assertEq(loanAgent.miner(), address(miner));
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent));
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner));
        assertEq(miner.currentOwner(), address(loanAgent));
        assertEq(loanAgent.owner(), alice);

        vm.stopPrank();
    }

    // function testFailDuplicateLoanAgents() public {
    //     vm.startPrank(alice);
    //     loanAgentFactory.create(address(miner), alice);
    //     vm.stopPrank();
    //     loanAgentFactory.create(address(miner), bob);
    // }
}
