// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/IPool4626.sol";
import "src/Pool/PoolFactory.sol";
import "src/WFIL.sol";

contract LoanAgentBasicTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);
    address treasury = address(0x3);

    string poolName = "Test simple interest pool";
    uint256 baseInterestRate = 20e18;

    MockMiner miner;
    LoanAgentFactory loanAgentFactory;
    PoolFactory poolFactory;
    IPool4626 pool;
    ERC20 wFil;
    function setUp() public {
        wFil = new WFIL();
        poolFactory = new PoolFactory(wFil, treasury);
        pool = poolFactory.createSimpleInterestPool(poolName, baseInterestRate);

        loanAgentFactory = new LoanAgentFactory(address(poolFactory));
        miner = new MockMiner();
        miner.changeOwnerAddress(alice);
        vm.prank(alice);
        miner.changeOwnerAddress(alice);
        require(miner.currentOwner() == alice);
    }

    function testInitialState() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));

        assertEq(loanAgent.miner(), address(miner), "Loan agent's miner address should be the miner's address");
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent), "Loan agent factory should have the miner's address as an active miner");
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner), "Loan agent factory should have the loan agent's address as a registered loan agent");
        assertEq(miner.currentOwner(), alice, "The mock miner's current owner should be set to the original owner");
        assertEq(loanAgent.owner(), address(0), "The loan agent's default owner should be a zero address");

        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        vm.stopPrank();

        assertEq(loanAgent.miner(), address(miner), "After claiming ownership, the loan agent's miner should be the miner address");
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent), "After claiming ownership, the loan agent factory should have the miner's address as an active miner");
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner), "After claiming ownership, loan agent factory should have the loan agent's address as a registered loan agent");
        assertEq(miner.currentOwner(), address(loanAgent), "After claiming ownership, the miner's current owner should be the loan agent");
        assertEq(loanAgent.owner(), alice, "After claiming ownership, the loanAgent's owner should be the previous miner's owner");
    }

    function testFailClaimOwnership() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
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
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();

        loanAgent.revokeMinerOwnership(bob);

        // assertEq(loanAgent.miner(), address(miner));
        // assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent));
        // assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner));
        // assertEq(miner.currentOwner(), address(loanAgent));
        // assertEq(loanAgent.owner(), alice);

        // vm.stopPrank();
    }

    function testWithdrawNoBalance() public {
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        // configure the loan agent to be the miner's owner
        vm.startPrank(alice);
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
        vm.startPrank(alice);
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

contract LoanAgentTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);
    address treasury = address(0x3);
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;

    MockMiner miner;
    LoanAgentFactory loanAgentFactory;
    LoanAgent loanAgent;
    PoolFactory poolFactory;
    IPool4626 pool;
    WFIL wFil;
    function setUp() public {
        wFil = new WFIL();
        poolFactory = new PoolFactory(wFil, treasury);
        pool = poolFactory.createSimpleInterestPool(poolName, baseInterestRate);
        // bob is the investor, stakes 10 FIL
        vm.deal(bob, 11e18);
        uint256 stakeAmount = 10e18;
        vm.startPrank(bob);
        wFil.deposit{value: stakeAmount}();
        wFil.approve(address(pool), stakeAmount);
        pool.deposit(stakeAmount, bob);
        vm.stopPrank();

        loanAgentFactory = new LoanAgentFactory(address(poolFactory));
        miner = new MockMiner();
        miner.changeOwnerAddress(alice);
        vm.startPrank(alice);
        miner.changeOwnerAddress(alice);
        require(miner.currentOwner() == alice);
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
        uint256 prevBalance = wFil.balanceOf(address(loanAgent));
        assertEq(prevBalance, 0, "Loan agents balance should be 0 before borrowing");
        uint256 loanAmount = 1e18;
        vm.startPrank(alice);
        loanAgent.borrow(loanAmount, pool.id());
        uint256 currBalance = wFil.balanceOf(address(loanAgent));
        vm.roll(pool.getLoan(address(loanAgent)).startEpoch + 1);
        assertEq(pool.getLoan(address(loanAgent)).principal, currBalance, "Loan agent's principal should be the loan amount after borrowing.");
        assertEq(pool.getLoan(address(loanAgent)).interest, FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            baseInterestRate, 100e18
          ),
          loanAmount
        ), "Loan agent's principal should be the loan amount after borrowing.");
        assertGt(pool.loanBalance(address(loanAgent)), 0, "Loan agent's balance should be greater than 0 as epochs pass.");
    }

    function testRepay() public {
        uint256 loanAmount = 1e18;
        vm.startPrank(alice);
        loanAgent.borrow(loanAmount, pool.id());
        // roll 100 epochs forward so we have a balance
        vm.roll(pool.getLoan(address(loanAgent)).startEpoch + 100);
        uint256 owed = pool.loanBalance(address(loanAgent));
        loanAgent.repay(owed, pool.id());
        uint256 leftOver = pool.loanBalance(address(loanAgent));
        assertEq(leftOver, 0, "Loan balance should be 0 after `repay`ing the loanBalance amount");
    }
}
