// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Agent/Agent.sol";
import "src/Agent/AgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/IPool4626.sol";
import "src/Pool/PoolFactory.sol";
import "src/WFIL.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner1 = makeAddr("MINER_OWNER_1");
    address constant public AGENT_MANAGER = address(0);

    MockMiner miner;
    function setUp() public {
        vm.prank(investor1);
        miner = new MockMiner();
    }

    function testInitialState() public {
        vm.startPrank(investor1);

        // create an agent for miner
        Agent agent = Agent(
        payable(
            agentFactory.create()
        ));
        assertEq(miner.currentOwner(), investor1, "The mock miner's current owner should be set to the original owner");

        miner.changeOwnerAddress(address(agent));

        vm.stopPrank();

        // Authority must be established by the main calling contract
        setAgentPermissions(agent, investor1);

        vm.startPrank(investor1);
        agent.addMiner(address(miner));
        assertTrue(agent.hasMiner(address(miner)), "The miner should be registered as a miner on the agent");
        assertTrue(registry.minerRegistered(address(miner)), "After adding the miner the registry should have the miner's address as a registered miner");

        vm.stopPrank();

    }

    function testFailClaimOwnership() public {
        vm.startPrank(investor2);
        Agent agent = Agent(payable(agentFactory.create()));
        miner.changeOwnerAddress(address(agent));
        vm.stopPrank();

        vm.prank(investor1);
        vm.expectRevert(bytes("not authorized"));
        agent.addMiner(address(miner));
    }

    function testDuplicateMiner() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        vm.expectRevert(bytes("Miner already added"));
        agent.addMiner(address(miner));
        vm.stopPrank();
    }


    function testWithdrawNoBalance() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);

        uint256 prevBalance = address(agent).balance;
        vm.roll(20);
        agent.withdrawBalance(address(miner));
        uint256 currBalance = address(agent).balance;

        assertEq(currBalance, prevBalance);
        assertEq(prevBalance, 0);
        vm.stopPrank();
    }

    function testWithdrawBalance() public {
        // give funds to miner
        vm.deal(address(miner), 100 ether);
        // lock the funds to simulate rewards coming in over time
        vm.startPrank(investor1);

        miner.lockBalance(block.number, 100, 100 ether);
        vm.stopPrank();
        Agent agent = _configureAgent(investor1, miner);

        vm.startPrank(investor1);

        uint256 prevBalance = address(agent).balance;
        vm.roll(20);
        agent.withdrawBalance(address(miner));
        uint256 currBalance = address(agent).balance;

        assertGt(currBalance, prevBalance);
        assertEq(prevBalance, 0);
        vm.stopPrank();
    }
}

contract LoanAgentTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    MockMiner miner;
    Agent agent;
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
        vm.stopPrank();

        agent = _configureAgent(investor2, miner);
    }

    function testBorrow() public {
        uint256 prevBalance = wFIL.balanceOf(address(agent));
        assertEq(prevBalance, 0, "Agents balance should be 0 before borrowing");
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        agent.borrow(loanAmount, pool.id());
        uint256 currBalance = wFIL.balanceOf(address(agent));
        vm.roll(pool.getLoan(address(agent)).startEpoch + 1);
        assertEq(pool.getLoan(address(agent)).principal, currBalance, "Agent's principal should be the loan amount after borrowing.");
        assertEq(pool.getLoan(address(agent)).interest, FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            baseInterestRate, 100e18
          ),
          loanAmount
        ), "Agent's principal should be the loan amount after borrowing.");
        (uint256 bal, ) = pool.loanBalance(address(agent));
        assertGt(bal, 0, "Agent's balance should be greater than 0 as epochs pass.");
    }

    function testRepay() public {
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        agent.borrow(loanAmount, pool.id());
        // roll 100 epochs forward so we have a balance
        vm.roll(pool.getLoan(address(agent)).startEpoch + 100);
        (uint256 owed, ) = pool.loanBalance(address(agent));
        agent.repay(owed, pool.id());
        (uint256 leftOver, ) = pool.loanBalance(address(agent));
        assertEq(leftOver, 0, "Loan balance should be 0 after `repay`ing the loanBalance amount");
    }

    function testFailBorrowInPenalty() public {
        uint256 loanAmount = 1e18;
        vm.startPrank(investor2);
        agent.borrow(loanAmount, pool.id());

        vm.roll(pool.gracePeriod() + 2);
        bool inPenalty = stats.hasPenalties(address(agent));
        assertTrue(inPenalty);
        agent.borrow(loanAmount, pool.id());
    }

    function testInPenaltyWithNoLoans() public {
        vm.startPrank(investor2);
        vm.roll(pool.gracePeriod() + 2);
        bool inPenalty = stats.hasPenalties(address(agent));
        assertFalse(inPenalty);
    }

    function testFailRevokeOwnershipWithExistingLoans() public {
        address newOwner = makeAddr("INVESTOR_2");
        vm.startPrank(investor1);
        agent.revokeOwnership(newOwner, address(miner));
    }

    function testFailRevokeOwnershipFromWrongOwner() public {
        address newOwner = makeAddr("TEST");
        vm.startPrank(newOwner);
        agent.revokeOwnership(newOwner, address(miner));
    }
}
