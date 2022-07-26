// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/Pool.sol";
import "src/Pool/PoolFactory.sol";

contract LoanAgentBasicTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);

    string poolName = "FIRST POOL NAME";

    MockMiner miner;
    LoanAgentFactory loanAgentFactory;
    PoolFactory poolFactory;
    function setUp() public {
        poolFactory = new PoolFactory();
        Pool pool = new Pool(1 ether, poolName);
        poolFactory.create(address(pool));

        loanAgentFactory = new LoanAgentFactory(address(pool));
        miner = new MockMiner();
        miner.changeOwnerAddress(alice);
        vm.prank(alice);
        miner.changeOwnerAddress(alice);
        require(miner.currentOwner() == alice);
    }

    function testInitialState() public {
        vm.startPrank(alice);
        LoanAgent loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));

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

        assertEq(loanAgent.miner(), address(miner));
        assertEq(loanAgentFactory.activeMiners(address(miner)), address(loanAgent));
        assertEq(loanAgentFactory.loanAgents(address(loanAgent)), address(miner));
        assertEq(miner.currentOwner(), address(loanAgent));
        assertEq(loanAgent.owner(), alice);

        vm.stopPrank();
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
    string poolName = "FIRST POOL NAME";

    MockMiner miner;
    LoanAgentFactory loanAgentFactory;
    LoanAgent loanAgent;
    PoolFactory poolFactory;
    Pool pool;
    function setUp() public {
        poolFactory = new PoolFactory();
        pool = new Pool(1 ether, poolName);
        poolFactory.create(address(pool));
        // bob is the investor, stakes 10 FIL
        vm.deal(bob, 11 ether);
        uint256 stakeAmount = 10 ether;
        vm.startPrank(bob);
        pool.stake{value: stakeAmount}(bob);
        vm.stopPrank();

        loanAgentFactory = new LoanAgentFactory(address(poolFactory));
        miner = new MockMiner();
        miner.changeOwnerAddress(alice);
        vm.startPrank(alice);
        miner.changeOwnerAddress(alice);
        require(miner.currentOwner() == alice);
        // give funds to miner
        vm.deal(address(miner), 100 ether);
        // lock the funds to simulate rewards coming in over time
        miner.lockBalance(block.number, 100, 100 ether);

        loanAgent = LoanAgent(payable(loanAgentFactory.create(address(miner))));
        // configure the loan agent to be the miner's owner
        miner.changeOwnerAddress(address(loanAgent));
        loanAgent.claimOwnership();
        vm.stopPrank();
    }

    function testTakeLoan() public {
        uint256 prevBalance = address(loanAgent).balance;
        assertEq(prevBalance, 0);
        uint256 loanAmount = 1 ether;
        vm.startPrank(alice);
        loanAgent.takeLoan(loanAmount, pool.id());
        uint256 currBalance = address(loanAgent).balance;
        assertGt(currBalance, prevBalance);
        assertEq(prevBalance, 0);
        assertGt(pool._loans(address(loanAgent)), 0);
    }

    function testPaydownDebt() public {
        uint256 loanAmount = 1 ether;
        vm.startPrank(alice);
        loanAgent.takeLoan(loanAmount, pool.id());
        uint256 owed = pool._loans(address(loanAgent));
        uint256 paydown = loanAgent.paydownDebt(pool.id());

        uint256 leftOver = pool._loans(address(loanAgent));
        assertEq(owed - leftOver, pool.repaymentAmount(loanAmount) - paydown);
    }
}
