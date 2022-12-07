// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/IPool4626.sol";
import "src/Pool/PoolFactory.sol";
import "src/WFIL.sol";

import "./BaseTest.sol";

contract LoanAgentBasicTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    MockMiner miner;
    function setUp() public {
        vm.prank(investor1);
        miner = new MockMiner();
    }

    function testInitialState() public {
        vm.startPrank(investor1);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));

        assertEq(loanAgent.miner(), address(miner), "Loan agent's miner address should be the miner's address");
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent), "Loan agent factory should have the miner's address as an active miner");
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner), "Loan agent factory should have the loan agent's address as a registered loan agent");
        assertEq(miner.currentOwner(), investor1, "The mock miner's current owner should be set to the original owner");
        assertEq(loanAgent.owner(), address(0), "The loan agent's default owner should be a zero address");

        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        vm.stopPrank();

        assertEq(loanAgent.miner(), address(miner), "After claiming ownership, the loan agent's miner should be the miner address");
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent), "After claiming ownership, the loan agent factory should have the miner's address as an active miner");
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner), "After claiming ownership, loan agent factory should have the loan agent's address as a registered loan agent");
        assertEq(miner.currentOwner(), address(loanAgent), "After claiming ownership, the miner's current owner should be the loan agent");
        assertEq(loanAgent.owner(), investor1, "After claiming ownership, the loanAgent's owner should be the previous miner's owner");
    }

    function testFailClaimOwnership() public {
        vm.startPrank(investor2);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        miner.changeOwnerAddress(address(loanAgent));
        vm.stopPrank();

        vm.prank(investor1);
        loanAgent.claimOwnership();
    }

    function testDuplicateLoanAgents() public {
        address loanAgentAddr = loanAgentFactory.create(address(miner));
        address loanAgentAddr2 = loanAgentFactory.create(address(miner));

        assertEq(loanAgentAddr, loanAgentAddr2);
    }

    function testRevokeOwnership() public {
        vm.startPrank(investor1);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        uint256 prevCount = loanAgentFactory.count();
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        loanAgent.revokeOwnership(investor1);

        assertEq(loanAgent.miner(), address(miner));
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(0));
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(0));
        assertEq(loanAgentFactory.count(), prevCount - 1);
        assertEq(miner.currentOwner(), address(loanAgent));
        assertEq(loanAgent.owner(), investor1);

        vm.stopPrank();
    }

    function testWithdrawNoBalance() public {
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        // configure the loan agent to be the miner's owner
        vm.startPrank(investor1);
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();

        uint256 prevBalance = address(loanAgent).balance;
        vm.roll(20);
        loanAgent.withdrawBalance();
        uint256 currBalance = address(loanAgent).balance;

        assertEq(currBalance, prevBalance);
        assertEq(prevBalance, 0);
    }

    function testWithdrawBalance() public {
        // give funds to miner
        vm.deal(address(miner), 100 ether);
        // lock the funds to simulate rewards coming in over time
        vm.startPrank(investor1);
        miner.lockBalance(block.number, 100, 100 ether);

        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        // configure the loan agent to be the miner's owner
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();

        uint256 prevBalance = address(loanAgent).balance;
        vm.roll(20);
        loanAgent.withdrawBalance();
        uint256 currBalance = address(loanAgent).balance;

        assertGt(currBalance, prevBalance);
        assertEq(prevBalance, 0);
    }
}

contract LoanAgentTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    MockMiner miner;
    LoanAgent loanAgent;
    IPool4626 pool;

    function setUp() public {
        pool = poolFactory.createSimpleInterestPool(poolName, baseInterestRate);
        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        uint256 stakeAmount = 10e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount}();
        wFIL.approve(address(pool), stakeAmount);
        pool.deposit(stakeAmount, investor1);
        vm.stopPrank();
        miner = new MockMiner();
        miner.changeOwnerAddress(investor2);
        vm.startPrank(investor2);
        miner.changeOwnerAddress(investor2);
        require(miner.currentOwner() == investor2);
        // give funds to miner
        vm.deal(address(miner), 100e18);
        // lock the funds to simulate rewards coming in over time
        miner.lockBalance(block.number, 100, 100 ether);

        loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        // configure the loan agent to be the miner's owner
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        vm.stopPrank();
    }

    function testBorrow() public {
        uint256 prevBalance = wFIL.balanceOf(address(loanAgent));
        assertEq(prevBalance, 0, "Loan agents balance should be 0 before borrowing");
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        loanAgent.borrow(loanAmount, pool.id());
        uint256 currBalance = wFIL.balanceOf(address(loanAgent));
        vm.roll(pool.getLoan(address(loanAgent)).startEpoch + 1);
        assertEq(pool.getLoan(address(loanAgent)).principal, currBalance, "Loan agent's principal should be the loan amount after borrowing.");
        assertEq(pool.getLoan(address(loanAgent)).interest, FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            baseInterestRate, 100e18
          ),
          loanAmount
        ), "Loan agent's principal should be the loan amount after borrowing.");
        (uint256 bal, ) = pool.loanBalance(address(loanAgent));
        assertGt(bal, 0, "Loan agent's balance should be greater than 0 as epochs pass.");
    }

    function testRepay() public {
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        loanAgent.borrow(loanAmount, pool.id());
        // roll 100 epochs forward so we have a balance
        vm.roll(pool.getLoan(address(loanAgent)).startEpoch + 100);
        (uint256 owed, ) = pool.loanBalance(address(loanAgent));
        loanAgent.repay(owed, pool.id());
        (uint256 leftOver, ) = pool.loanBalance(address(loanAgent));
        assertEq(leftOver, 0, "Loan balance should be 0 after `repay`ing the loanBalance amount");
    }

    function testFailBorrowInPenalty() public {
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        loanAgent.borrow(loanAmount, pool.id());

        vm.roll(pool.gracePeriod() + 2);
        bool inPenalty = stats.hasPenalties(address(loanAgent));
        assertTrue(inPenalty);
        loanAgent.borrow(loanAmount, pool.id());
    }

    function testInPenaltyWithNoLoans() public {
        vm.startPrank(investor2);
        vm.roll(pool.gracePeriod() + 2);
        bool inPenalty = stats.hasPenalties(address(loanAgent));
        assertFalse(inPenalty);
    }

    function testFailRevokeOwnershipWithExistingLoans() public {
        address newOwner = makeAddr("INVESTOR_2");
        vm.startPrank(investor1);
        loanAgent.revokeOwnership(newOwner);
    }

    function testFailRevokeOwnershipFromWrongOwner() public {
        address newOwner = makeAddr("TEST");
        vm.startPrank(newOwner);
        loanAgent.revokeOwnership(newOwner);
    }

    function testFailPoolFactoryRevokeOwnershipWrongOwner() public {
        address newOwner = makeAddr("TEST");
        vm.startPrank(newOwner);
        loanAgentFactory.revokeOwnership(newOwner);
    }
}
