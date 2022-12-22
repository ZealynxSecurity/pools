// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Authority} from "src/Auth/Auth.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {WFIL} from "src/WFIL.sol";

import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {Account} from "src/Types/Structs/Account.sol";

import {ROUTE_AGENT_FACTORY_ADMIN, ROUTE_MINER_REGISTRY} from "src/Constants/Routes.sol";
import "src/Constants/FuncSigs.sol";
import "src/Constants/Roles.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    MockMiner miner;
    function setUp() public {
        vm.prank(investor1);
        miner = new MockMiner();
     }

    function testInitialState() public {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        IMinerRegistry registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
        vm.startPrank(investor1);

        // create an agent for miner
        Agent agent = Agent(
        payable(
            agentFactory.create(address(0))
        ));
        assertEq(miner.currentOwner(), investor1, "The mock miner's current owner should be set to the original owner");

        miner.changeOwnerAddress(address(agent));

        vm.stopPrank();

        vm.startPrank(investor1);
        agent.addMiner(address(miner));
        assertTrue(agent.hasMiner(address(miner)), "The miner should be registered as a miner on the agent");
        assertTrue(registry.minerRegistered(address(miner)), "After adding the miner the registry should have the miner's address as a registered miner");

        Authority customAuthority = coreAuthority.getTargetCustomAuthority(address(agent));

        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_ADD_MINER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_REMOVE_MINER_ADDR_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_REMOVE_MINER_INDEX_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_WITHDRAW_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_REVOKE_OWNERSHIP_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_BORROW_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_REPAY_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_MINT_POWER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_BURN_POWER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), ENABLE_OPERATOR_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), DISABLE_OPERATOR_SELECTOR));
        // Agent should be able to set roles on its own authorities
        assertTrue(customAuthority.canCall(address(agent), address(customAuthority), AUTH_SET_USER_ROLE_SELECTOR));

        address nonOperatorOwner = makeAddr("NON_OPERATOR_OWNER");
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_ADD_MINER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_REMOVE_MINER_ADDR_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_REMOVE_MINER_INDEX_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_WITHDRAW_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_REVOKE_OWNERSHIP_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_BORROW_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_REPAY_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_MINT_POWER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_BURN_POWER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), ENABLE_OPERATOR_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), DISABLE_OPERATOR_SELECTOR));

        vm.stopPrank();
    }

    function testClashingAgentRoles() public {
        (Agent agent1,) = configureAgent(investor1);
        (Agent agent2,) = configureAgent(investor2);

        Authority agent1Authority = coreAuthority.getTargetCustomAuthority(address(agent1));
        Authority agent2Authority = coreAuthority.getTargetCustomAuthority(address(agent2));

        assertTrue(agent1Authority.canCall(investor1, address(agent1), AGENT_ADD_MINER_SELECTOR));
        assertTrue(agent2Authority.canCall(investor2, address(agent2), AGENT_WITHDRAW_SELECTOR));

        assertTrue(!(agent1Authority.canCall(investor2, address(agent1), AGENT_ADD_MINER_SELECTOR)));
        assertTrue(!(agent2Authority.canCall(investor1, address(agent2), AGENT_WITHDRAW_SELECTOR)));

        // the global authority should receive the same result
        assertTrue(coreAuthority.canCall(investor1, address(agent1), AGENT_ADD_MINER_SELECTOR));
        assertTrue(!(coreAuthority.canCall(investor2, address(agent1), AGENT_ADD_MINER_SELECTOR)));

        assertTrue(coreAuthority.canCall(investor2, address(agent2), AGENT_WITHDRAW_SELECTOR));
        assertTrue(!(coreAuthority.canCall(investor1, address(agent2), AGENT_WITHDRAW_SELECTOR)));
    }

    function testFailClaimOwnership() public {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.startPrank(investor2);
        Agent agent = Agent(payable(agentFactory.create(address(0))));
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

    function testEnableOwner() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address owner = makeAddr("OWNER");
        agent.enableOwner(owner);
        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );
        assertTrue(customAuthority.doesUserHaveRole(owner, ROLE_AGENT_OWNER));
    }

    function testDisableOwner() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address owner = makeAddr("OWNER");
        agent.enableOwner(owner);

        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );

        assertTrue(customAuthority.doesUserHaveRole(owner, ROLE_AGENT_OWNER));
        agent.disableOwner(owner);
        assertTrue(!customAuthority.doesUserHaveRole(owner, ROLE_AGENT_OWNER));
    }

    function testEnableOperator() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address operator = makeAddr("OPERATOR");
        agent.enableOperator(operator);
        MultiRolesAuthority customAuthority = MultiRolesAuthority(address(coreAuthority.getTargetCustomAuthority(address(agent))));
        assertTrue(customAuthority.doesUserHaveRole(operator, ROLE_AGENT_OPERATOR));
        assertTrue(!(customAuthority.doesUserHaveRole(operator, ROLE_AGENT_OWNER)));
    }

    function testDisableOperator() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address operator = makeAddr("OPERATOR");
        agent.enableOperator(operator);

        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );

        assertTrue(customAuthority.doesUserHaveRole(operator, ROLE_AGENT_OPERATOR));
        assertTrue(!(customAuthority.doesUserHaveRole(operator, ROLE_AGENT_OWNER)));

        agent.disableOperator(operator);
        assertTrue(!customAuthority.doesUserHaveRole(operator, ROLE_AGENT_OPERATOR));
    }

    function testRouterConfigured() public {
        (Agent agent,) = configureAgent(investor1);
        address r = IRouterAware(address(agent)).router();
        assertEq(IRouterAware(address(agent)).router(), address(r));
    }
}

contract AgentTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    MockMiner miner;
    Agent agent;
    IPool pool;

    function setUp() public {
        IPoolFactory poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
        pool = poolFactory.createPool(
            "TEST",
            "TEST",
            ZERO_ADDRESS,
            ZERO_ADDRESS
        );
        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        uint256 stakeAmount = 10e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount}();
        wFIL.approve(address(pool), stakeAmount);
        // TODO: Deposit into pool
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

    // function testBorrow() public {
    //     uint256 prevBalance = wFIL.balanceOf(address(agent));
    //     assertEq(prevBalance, 0, "Agents balance should be 0 before borrowing");
    //     uint256 loanAmount = 1e18;

    //     (VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) = issueGenericVC(address(agent));
    //     vm.startPrank(investor2);
      //     agent.borrow(loanAmount, 0, vc, 0, v, r, s);
    //     uint256 currBalance = wFIL.balanceOf(address(agent));
    //     Account memory account = pool.getAccount(address(agent));
    //     vm.roll(account.startEpoch + 1);
        // TODO: Add Assertions
        // vm.roll(pool.getLoan(address(agent)).startEpoch + 1);
        // assertEq(
        //     pool.getLoan(address(agent)).principal, currBalance,
        //     "Agent's principal should be the loan amount after borrowing."
        // );
        // assertEq(
        //     pool.getLoan(address(agent)).interest,
        //     FixedPointMathLib.mulWadDown(
        //         FixedPointMathLib.divWadDown(
        //             baseInterestRate, 100e18
        //         ),
        //         loanAmount
        //     ),
        //     "Agent's principal should be the loan amount after borrowing."
        // );
        // (uint256 bal, ) = pool.loanBalance(address(agent));
        // assertGt(bal, 0, "Agent's balance should be greater than 0 as epochs pass.");
    // }

    // function testRepay() public {
    //     uint256 loanAmount = 1e18;
    //     (VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) = issueGenericVC(address(agent));

    //     vm.startPrank(investor2);
    //     agent.borrow(loanAmount, 0, vc, 0, v, r, s);
    //     // roll 100 epochs forward so we have a balance
    //     Account memory account = pool.getAccount(address(agent));
    //     vm.roll(account.startEpoch + 100);
    //     uint256 owed = pool.getAgentBorrowed(address(agent));
    //     pool.makePayment(address(agent), vc);
    //     // TODO: Confirm that payment brought the duedate of the next payment into the future.
    // }

    // function testFailBorrowInPenalty() internal {
    //     Stats stats = Stats(IRouter(router).getRoute(ROUTE_STATS));
    //     uint256 loanAmount = 1e18;
    //     vm.startPrank(investor2);
    //     agent.borrow(loanAmount, pool.id());
    // }

    // function testInPenaltyWithNoLoans() public {
    //     Stats stats = Stats(IRouter(router).getRoute(ROUTE_STATS));
    //     vm.startPrank(investor2);
    //     vm.roll(pool.gracePeriod() + 2);
    //     bool inPenalty = stats.hasPenalties(address(agent));
    //     assertFalse(inPenalty);
    // }

    // function testFailRevokeOwnershipWithExistingLoans() public {
    //     address newOwner = makeAddr("INVESTOR_2");
    //     vm.startPrank(investor1);
    //     agent.revokeOwnership(newOwner, address(miner));
    // }

    // function testFailRevokeOwnershipFromWrongOwner() public {
    //     address newOwner = makeAddr("TEST");
    //     vm.startPrank(newOwner);
    //     agent.revokeOwnership(newOwner, address(miner));
    // }
}

contract AgentFactoryRolesTest is BaseTest {
    IAgentFactory agentFactory;
    function testSetVerifierName() public {
        agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        string memory NEW_VERIFIED_NAME = "glif.io";
        string memory NEW_VERIFIED_VERSION = "1";
        vm.prank(IRouter(router).getRoute(ROUTE_AGENT_FACTORY_ADMIN));
        agentFactory.setVerifierName(NEW_VERIFIED_NAME, NEW_VERIFIED_VERSION);
        assertEq(agentFactory.verifierName(), NEW_VERIFIED_NAME);
        assertEq(agentFactory.verifierVersion(), NEW_VERIFIED_VERSION);
    }

    function testFailSetVerifierName() public {
        string memory NEW_VERIFIED_NAME = "glif.io";
        string memory NEW_VERIFIED_VERSION = "1";
        agentFactory.setVerifierName(NEW_VERIFIED_NAME, NEW_VERIFIED_VERSION);
        assertEq(agentFactory.verifierName(), NEW_VERIFIED_NAME);
        assertEq(agentFactory.verifierVersion(), NEW_VERIFIED_VERSION);
    }
}
