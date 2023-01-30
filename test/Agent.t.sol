// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "src/MockMiner.sol";
import {Authority} from "src/Auth/Auth.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Auth} from "src/Auth/Auth.sol";
import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {WFIL} from "src/WFIL.sol";

import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Window} from "src/Types/Structs/Window.sol";

import {ROUTE_AGENT_FACTORY_ADMIN, ROUTE_MINER_REGISTRY} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
import {Roles} from "src/Constants/Roles.sol";
import {Decode} from "src/Errors.sol";
import "src/Constants/FuncSigs.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    using AccountHelpers for Account;
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    MockMiner miner;
    address[] miners = new address[](1);
    function setUp() public {
        vm.prank(investor1);
        miner = new MockMiner();
        miners[0] = address(miner);
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
        assertEq(miner.get_owner(address(miner)), investor1, "The mock miner's current owner should be set to the original owner");

        miner.change_owner_address(address(miner), address(agent));

        agent.addMiners(miners);
        assertTrue(agent.hasMiner(address(miner)), "The miner should be registered as a miner on the agent");
        assertTrue(registry.minerRegistered(agent.id(), address(miner)), "After adding the miner the registry should have the miner's address as a registered miner");

        Authority customAuthority = coreAuthority.getTargetCustomAuthority(address(agent));

        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_ADD_MINERS_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_REMOVE_MINER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_WITHDRAW_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_BORROW_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_MINT_POWER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), AGENT_BURN_POWER_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), SET_OPERATOR_ROLE_SELECTOR));
        assertTrue(customAuthority.canCall(address(investor1), address(agent), SET_OWNER_ROLE_SELECTOR));
        // Agent should be able to set roles on its own authorities
        assertTrue(customAuthority.canCall(address(agent), address(customAuthority), AUTH_SET_USER_ROLE_SELECTOR));

        address nonOperatorOwner = makeAddr("NON_OPERATOR_OWNER");
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_ADD_MINERS_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_REMOVE_MINER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_WITHDRAW_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_BORROW_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_MINT_POWER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), AGENT_BURN_POWER_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), SET_OPERATOR_ROLE_SELECTOR));
        assertTrue(!customAuthority.canCall(nonOperatorOwner, address(agent), SET_OWNER_ROLE_SELECTOR));

        vm.stopPrank();
    }

    function testClashingAgentRoles() public {
        (Agent agent1,) = configureAgent(investor1);
        (Agent agent2,) = configureAgent(investor2);

        Authority agent1Authority = coreAuthority.getTargetCustomAuthority(address(agent1));
        Authority agent2Authority = coreAuthority.getTargetCustomAuthority(address(agent2));

        assertTrue(agent1Authority.canCall(investor1, address(agent1), AGENT_BORROW_SELECTOR));
        assertTrue(agent2Authority.canCall(investor2, address(agent2), AGENT_BORROW_SELECTOR));

        assertTrue(!(agent1Authority.canCall(investor2, address(agent1), AGENT_BORROW_SELECTOR)));
        assertTrue(!(agent2Authority.canCall(investor1, address(agent2), AGENT_BORROW_SELECTOR)));

        // the global authority should receive the same result
        assertTrue(coreAuthority.canCall(investor1, address(agent1), AGENT_BORROW_SELECTOR));
        assertTrue(!(coreAuthority.canCall(investor2, address(agent1), AGENT_BORROW_SELECTOR)));

        assertTrue(coreAuthority.canCall(investor2, address(agent2), AGENT_BORROW_SELECTOR));
        assertTrue(!(coreAuthority.canCall(investor1, address(agent2), AGENT_BORROW_SELECTOR)));
    }

    function testFailClaimOwnership() public {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.startPrank(investor2);
        Agent agent = Agent(payable(agentFactory.create(address(0))));
        miner.change_owner_address(address(miner), address(agent));
        vm.stopPrank();

        vm.prank(investor1);
        vm.expectRevert(bytes("not authorized"));
        agent.addMiners(miners);
    }

    function testDuplicateMiner() public {
        Agent agent = _configureAgent(investor1, miner);

        // hack to get the miner's next_owner to be the agent again so we can attempt to add duplicate miners without running into other errors
        // although i dont think this situation could ever occur (because agent would already own the miner at this point)
        vm.prank(address(agent));
        miner.change_owner_address(address(miner), address(agent));

        vm.startPrank(investor1);
        vm.expectRevert(bytes("Miner already registered"));
        agent.addMiners(miners);
        vm.stopPrank();
    }

    function testWithdrawNoBalance() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);

        uint256 prevBalance = address(agent).balance;
        vm.roll(20);
        agent.withdrawBalance(address(miner), 0);
        uint256 currBalance = address(agent).balance;

        assertEq(currBalance, prevBalance);
        assertEq(prevBalance, 0);
        vm.stopPrank();
    }

    function testEnableOwner() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address owner = makeAddr("OWNER");
        agent.setOwnerRole(owner, true);
        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );
        assertTrue(customAuthority.doesUserHaveRole(owner, uint8(Roles.ROLE_AGENT_OWNER)));
    }

    function testDisableOwner() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address owner = makeAddr("OWNER");
        agent.setOwnerRole(owner, true);

        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );

        assertTrue(customAuthority.doesUserHaveRole(owner, uint8(Roles.ROLE_AGENT_OWNER)));
        agent.setOwnerRole(owner, false);
        assertTrue(!customAuthority.doesUserHaveRole(owner, uint8(Roles.ROLE_AGENT_OWNER)));
    }

    function testEnableOperator() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address operator = makeAddr("OPERATOR");
        agent.setOperatorRole(operator, true);
        MultiRolesAuthority customAuthority = MultiRolesAuthority(address(coreAuthority.getTargetCustomAuthority(address(agent))));
        assertTrue(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR)));
        assertTrue(!(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_AGENT_OWNER))));
    }

    function testDisableOperator() public {
        Agent agent = _configureAgent(investor1, miner);
        vm.startPrank(investor1);
        address operator = makeAddr("OPERATOR");
        agent.setOperatorRole(operator, true);

        MultiRolesAuthority customAuthority = MultiRolesAuthority(
            address(coreAuthority.getTargetCustomAuthority(address(agent)))
        );

        assertTrue(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR)));
        assertTrue(!(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_AGENT_OWNER))));

        agent.setOperatorRole(operator, false);
        assertTrue(!customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR)));
    }

    function testRouterConfigured() public {
        (Agent agent,) = configureAgent(investor1);
        address r = IRouterAware(address(agent)).router();
        assertEq(IRouterAware(address(agent)).router(), address(r));
    }

    function testReceive() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (Agent agent,) = configureAgent(investor1);
        uint256 agentFILBal = address(agent).balance;

        vm.prank(investor1);
        (bool sent,) = payable(address(agent)).call{value: transferAmt}("");
        assertTrue(sent);
        assertEq(address(agent).balance, agentFILBal + transferAmt);
    }

    function testFallback() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (Agent agent,) = configureAgent(investor1);
        uint256 agentFILBal = address(agent).balance;

        vm.prank(investor1);
        (bool sent,) = payable(address(agent)).call{value: transferAmt}(bytes("fdsa"));
        assertTrue(sent);
        assertEq(address(agent).balance, agentFILBal + transferAmt);
    }

    function testPullFundsFromMiners() public {
        Agent agent = _configureAgent(investor1, miner);

        address[] memory minersToAdd = new address[](1);
        // prepare a second miner to draw funds from
        MockMiner secondMiner = new MockMiner();

        secondMiner.change_owner_address(address(secondMiner), address(agent));
        require(secondMiner.next_owner(address(secondMiner)) == address(agent), "Agent not set as owner");
        minersToAdd[0] = address(secondMiner);

        vm.prank(investor1);
        agent.addMiners(minersToAdd);
        // give the miners some funds to pull
        vm.deal(address(miner), 1e18);
        vm.deal(address(secondMiner), 2e18);

        IERC20 wFIL20 = IERC20(address(wFIL));

        assertEq(wFIL20.balanceOf(address(agent)), 0);

        // create calldata for pullFundsFromMiners
        address[] memory _miners = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1e18;
        _amounts[1] = 1e18;
        _miners[0] = address(miner);
        _miners[1] = address(secondMiner);
        vm.prank(investor1);
        agent.pullFundsFromMiners(_miners, _amounts);

        assertEq(address(agent).balance, 2e18);
        assertEq(address(miner).balance, 0);
        assertEq(address(secondMiner).balance, 1e18);
    }

    function testPullMaxFundsFromMiners() public {
        Agent agent = _configureAgent(investor1, miner);

        address[] memory minersToAdd = new address[](1);
        // prepare a second miner to draw funds from
        MockMiner secondMiner = new MockMiner();

        secondMiner.change_owner_address(address(secondMiner), address(agent));
        require(secondMiner.next_owner(address(secondMiner)) == address(agent), "Agent not set as owner");
        minersToAdd[0] = address(secondMiner);

        vm.prank(investor1);
        agent.addMiners(minersToAdd);
        // give the miners some funds to pull
        vm.deal(address(miner), 1e18);
        vm.deal(address(secondMiner), 2e18);

        IERC20 wFIL20 = IERC20(address(wFIL));

        assertEq(wFIL20.balanceOf(address(agent)), 0);

        // create calldata for pullFundsFromMiners
        address[] memory _miners = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        // passing 0 as the amount should draw max funds
        _amounts[0] = 0;
        _amounts[1] = 0;
        _miners[0] = address(miner);
        _miners[1] = address(secondMiner);
        vm.prank(investor1);
        agent.pullFundsFromMiners(_miners, _amounts);

        assertEq(address(agent).balance, 3e18);
        assertEq(address(miner).balance, 0);
        assertEq(address(secondMiner).balance, 0);
    }

    function testPushFundsToMiners() public {
        Agent agent = _configureAgent(investor1, miner);

        address[] memory minersToAdd = new address[](1);
        // prepare a second miner to draw funds from
        MockMiner secondMiner = new MockMiner();

        secondMiner.change_owner_address(address(secondMiner), address(agent));
        require(secondMiner.next_owner(address(secondMiner)) == address(agent), "Agent not set as owner");
        minersToAdd[0] = address(secondMiner);
        vm.deal(investor1, 3e18);

        vm.startPrank(investor1);
        agent.addMiners(minersToAdd);
        // give the agent some funds to push
        wFIL.deposit{value: 3e18}();
        wFIL.transfer(address(agent), 3e18);

        IERC20 wFIL20 = IERC20(address(wFIL));

        assertEq(wFIL20.balanceOf(address(agent)), 3e18);

        // create calldata for pullFundsFromMiners
        address[] memory _miners = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = 1e18;
        _amounts[1] = 2e18;
        _miners[0] = address(miner);
        _miners[1] = address(secondMiner);
        agent.pushFundsToMiners(_miners, _amounts);

        vm.stopPrank();

        assertEq(wFIL20.balanceOf(address(agent)), 0);
        assertEq(address(miner).balance, 1e18);
        assertEq(address(secondMiner).balance, 2e18);
    }
}

contract AgentTest is BaseTest {
    using AccountHelpers for Account;
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
    string poolName = "FIRST POOL NAME";
    address poolOperator = makeAddr("POOL_OPERATOR");
    uint256 baseInterestRate = 20e18;
    uint256 stakeAmount;

    IAgent agent;
    MockMiner miner;
    IPool pool;
    IERC4626 pool4626;
    SignedCredential signedCred;

    address powerToken;


    function setUp() public {
        powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
        pool = createPool(
            "TEST",
            "TEST",
            poolOperator,
            2e18
        );
        pool4626 = IERC4626(address(pool));

        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        stakeAmount = 10e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount}();
        wFIL.approve(address(pool), stakeAmount);
        pool4626.deposit(stakeAmount, investor1);
        vm.stopPrank();

        (agent, miner) = configureAgent(minerOwner);
        // mint some power for the agent
        signedCred = issueGenericSC(address(agent));
        vm.startPrank(address(agent));
        agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
        IERC20(powerToken).approve(address(pool), signedCred.vc.miner.qaPower);
        vm.stopPrank();
    }

    function testBorrow() public {
        uint256 borrowAmount = 0.5e18;

        uint256 borrowBlock = block.number;
        vm.prank(address(agent));
        agent.borrow(borrowAmount, 0, signedCred, signedCred.vc.miner.qaPower);
        uint256 currBalance = wFIL.balanceOf(address(agent));
        assertEq(currBalance, borrowAmount);

        Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
        assertEq(account.startEpoch, borrowBlock);
        assertGt(account.pmtPerEpoch(), 0);

        uint256 rate = pool.implementation().getRate(
            borrowAmount,
            signedCred.vc.miner.qaPower,
            GetRoute.agentPolice(router).windowLength(),
            account,
            signedCred.vc
        );
        assertEq(account.perEpochRate, rate);
        assertEq(account.powerTokensStaked, signedCred.vc.miner.qaPower);
        assertEq(account.totalBorrowed, borrowAmount);

        // the agent staked all its power tokens in this example
        assertEq(
            IERC20(powerToken).balanceOf(address(agent)),
            0
        );

        assertEq(
            IERC20(powerToken).balanceOf(address(pool)),
            signedCred.vc.miner.qaPower
        );
    }

    function testExit() public {
        uint256 borrowAmount = 0.5e18;

        vm.startPrank(address(agent));
        agent.borrow(borrowAmount, 0, signedCred, signedCred.vc.miner.qaPower);
        wFIL.approve(address(pool), borrowAmount);
        agent.exit(0, borrowAmount, signedCred);
        vm.stopPrank();

        assertEq(IERC20(address(wFIL)).balanceOf(address(agent)), 0);
        assertEq(IERC20(address(wFIL)).balanceOf(address(pool)), stakeAmount);

        Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
        assertEq(account.totalBorrowed, 0);
        assertEq(account.powerTokensStaked, 0);
        assertEq(account.pmtPerEpoch(), 0);
    }
    function testRefinance() public {
        IPool pool2 = createPool(
            "TEST",
            "TEST",
            poolOperator,
            2e18
        );
        IERC4626 pool24626 = IERC4626(address(pool2));
        uint256 oldPoolID = pool.id();
        uint256 newPoolID = pool2.id();
        Account memory oldAccount;
        Account memory newAccount;
        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        stakeAmount = 10e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount}();
        wFIL.approve(address(pool2), stakeAmount);
        pool24626.deposit(stakeAmount, investor1);
        vm.stopPrank();

        uint256 borrowAmount = 0.5e18;

        vm.startPrank(address(agent));
        agent.borrow(borrowAmount, 0, signedCred, signedCred.vc.miner.qaPower);
        wFIL.approve(address(pool), borrowAmount);
        IERC20(powerToken).approve(address(pool2),  10000000000000000000);
        oldAccount = AccountHelpers.getAccount(router, address(agent), oldPoolID);
        assertEq(oldAccount.totalBorrowed, borrowAmount);
        agent.refinance(oldPoolID, newPoolID, 0, signedCred);
        oldAccount = AccountHelpers.getAccount(router, address(agent), oldPoolID);
        newAccount = AccountHelpers.getAccount(router, address(agent), newPoolID);
        assertEq(oldAccount.totalBorrowed, 0);
        assertEq(newAccount.totalBorrowed, borrowAmount);
        vm.stopPrank();

    }

    function testPullFundsFromMiners() public {}

    function testPushFundsToMiners() public {}
}

contract AgentPoliceTest is BaseTest {
    using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
    address poolOperator = makeAddr("POOL_OPERATOR");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    uint256 stakeAmount;

    IAgent agent;
    MockMiner miner;
    IPool pool;
    IERC4626 pool4626;
    SignedCredential signedCred;
    IAgentPolice police;

    address powerToken;


    function setUp() public {
        police = GetRoute.agentPolice(router);
        powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
        pool = createPool(
            "TEST",
            "TEST",
            poolOperator,
            2e18
        );
        pool4626 = IERC4626(address(pool));
        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        stakeAmount = 10e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount}();
        wFIL.approve(address(pool), stakeAmount);
        pool4626.deposit(stakeAmount, investor1);
        vm.stopPrank();

        (agent, miner) = configureAgent(minerOwner);
        // mint some power for the agent
        signedCred = issueGenericSC(address(agent));
        vm.startPrank(address(agent));
        agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
        IERC20(powerToken).approve(address(pool), signedCred.vc.miner.qaPower);
        vm.stopPrank();
    }

    function testNextPmtWindowDeadline() public {
        vm.roll(0);
        uint256 windowLength = police.windowLength();
        require(block.number < windowLength);

        uint256 nextPmtWindowDeadline = police.nextPmtWindowDeadline();
        // first window's deadline is the windowLength
        assertEq(nextPmtWindowDeadline, windowLength);

        vm.roll(block.number + windowLength + 10);
        nextPmtWindowDeadline = police.nextPmtWindowDeadline();
        assertEq(nextPmtWindowDeadline, windowLength * 2);
    }

    function testCheckOverPowered() public {
        uint256 powerTokenStake = 7.5e18;
        uint256 borrowAmount = 1000;
        uint256 newQAPower = 5e18;
        SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        // since agent has not staked any power tokens, the checkPower function should burn the tokens to the correct power amount
        police.checkPower(address(agent), sc);

        assertTrue(police.isOverPowered(address(agent)));
        assertTrue(police.isOverPowered(agent.id()));
        assertEq(
            IERC20(powerToken).balanceOf(address(agent)),
            signedCred.vc.miner.qaPower - powerTokenStake
        );
    }

    function testBorrowWhenOverPowered() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 5e18;
        SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        vm.prank(address(agent));
        try agent.borrow(borrowAmount, 0, sc, powerTokenStake) {
            assertTrue(false, "Call to borrow shoudl err when over pwered");
        } catch (bytes memory err) {
            (, string memory reason) = Decode.overPoweredError(err);
            assertEq(reason, "Agent: Cannot perform action while overpowered");
        }
    }

    function testRecoverOverPoweredByBurn() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 7.5e18;
        SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        vm.startPrank(address(agent));
        wFIL.approve(address(pool), borrowAmount);
        pool.exitPool(address(agent), signedCred, borrowAmount);
        agent.burnPower(2.5e18, signedCred);
        vm.stopPrank();
        police.checkPower(address(agent), sc);

        assertEq(IERC20(address(powerToken)).totalSupply(), 7.5e18);
        assertEq(police.isOverPowered(address(agent)), false);
    }

    function testRecoverOverPoweredStateIncreasePower() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 5e18;
        makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);
        SignedCredential memory sc = issueGenericSC(address(agent));

        police.checkPower(address(agent), sc);

        // no power was burned
        assertEq(IERC20(address(powerToken)).totalSupply(), signedCred.vc.miner.qaPower);
        assertEq(police.isOverPowered(address(agent)), false);    }

    function testRemoveMinerWhenOverPowered() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 5e18;
        makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        signedCred = issueGenericSC(address(agent));
        vm.startPrank(address(agent));
        try agent.removeMiner(address(this), address(miner), signedCred, signedCred) {
            assertTrue(false, "Call to borrow shoudl err when over pwered");
        } catch (bytes memory err) {
            (, string memory reason) = Decode.overPoweredError(err);
            assertEq(reason, "Agent: Cannot perform action while overpowered");
        }
    }

    function testForceBurnPowerWhenNotOverPowered() public {
        signedCred = issueGenericSC(address(agent));

        try police.forceBurnPower(address(agent), signedCred) {
            assertTrue(false, "Call to borrow shoudl err when over pwered");
        } catch (bytes memory err) {
            (, string memory reason) = Decode.notOverPoweredError(err);
            assertEq(reason, "AgentPolice: Agent is not overpowered");
        }
    }

    // agent does not end up overpowered because the agent has enough power tokens liquid to cover the decrease in real power
    function testForceBurnPowerWithAdequateBal() public {
        uint256 newQAPower = 5e18;

        MinerData memory minerData = MinerData(
            1e10, 20e18, 0.5e18, 10e18, 10e18, 0, 10, newQAPower, 5e18, 0, 0
        );

        VerifiableCredential memory _vc = VerifiableCredential(
            vcIssuer,
            address(agent),
            block.number,
            block.number + 100,
            1000,
            minerData
        );

        SignedCredential memory sc = issueSC(_vc);
        police.checkPower(address(agent), sc);
        assertTrue(police.isOverPowered(address(agent)), "Agent should be overed powered");
        police.forceBurnPower(address(agent), sc);

        assertEq(IPowerToken(powerToken).powerTokensMinted(agent.id()), sc.vc.miner.qaPower, "Agent should have 5e18 power tokens minted");
        assertEq(IERC20(address(powerToken)).totalSupply(), 5e18);
        assertEq(police.isOverPowered(address(agent)), false);
    }

    function testForceBurnPowerWithInadequateBal() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 5e18;
        SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        assertTrue(IERC20(address(powerToken)).balanceOf(address(agent)) == 2.5e18, "agent should have 2.5e18 power tokens");

        police.checkPower(address(agent), sc);
        police.forceBurnPower(address(agent), sc);
        // 2.5e18 tokens should get burned because thats the balance of the agent's power tokens
        assertTrue(IERC20(address(powerToken)).totalSupply() == 7.5e18, "total supply should be 7.5e18");
        assertTrue(IERC20(address(powerToken)).balanceOf(address(pool)) == powerTokenStake, "agent should have 0 power tokens");
        assertTrue(IERC20(address(powerToken)).balanceOf(address(agent)) == 0, "agent should have 0 power tokens");
        assertTrue(police.isOverPowered(address(agent)), "agent should be overpowered");
    }

    function testForcePullFundsFromMinersWhenNotOverleveraged() public {
        // prepare a second miner to draw funds from
        vm.prank(minerOwner);
        MockMiner secondMiner = new MockMiner();

        _agentClaimOwnership(address(agent), address(secondMiner), minerOwner);
        // give the miners some funds to pull
        vm.deal(address(miner), 1e18);
        vm.deal(address(secondMiner), 2e18);

        IERC20 wFIL20 = IERC20(address(wFIL));

        assertEq(wFIL20.balanceOf(address(agent)), 0);

        // create calldata for pullFundsFromMiners
        address[] memory _miners = new address[](2);
        _miners[0] = address(miner);
        _miners[1] = address(secondMiner);

        vm.prank(IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN));
        try police.forcePullFundsFromMiners(address(agent), _miners, new uint256[](2)) {
            assertTrue(false, "Call to borrow shoudl err when over pwered");
        } catch (bytes memory err) {
            (, string memory reason) = Decode.notOverLeveragedError(err);
            assertEq(reason, "AgentPolice: Agent is not overleveraged");
        }
    }

    function testForcePullFundsFromMiners() public {
        makeAgentOverLeveraged(1e18, 1e18);

        vm.prank(minerOwner);
        MockMiner secondMiner = new MockMiner();
        _agentClaimOwnership(address(agent), address(secondMiner), minerOwner);

        // give the miners some funds to pull
        uint256 FUND_AMOUNT = 50e18;
        vm.deal(address(miner), FUND_AMOUNT);
        vm.deal(address(secondMiner), FUND_AMOUNT);

        IERC20 wFIL20 = IERC20(address(wFIL));
        uint256 agentBalance = wFIL20.balanceOf(address(agent));
        // empty out agent wallet for testing
        vm.prank(address(agent));
        wFIL20.transfer(minerOwner, agentBalance);
        // assertEq(wFIL20.balanceOf(address(agent)), 0);

        // create calldata for pullFundsFromMiners
        address[] memory _miners = new address[](2);
        _miners[0] = address(miner);
        _miners[1] = address(secondMiner);

        uint256 FORCE_PULL_AMNT = 10e18;
        uint256[] memory _amounts = new uint256[](2);
        _amounts[0] = FORCE_PULL_AMNT;
        _amounts[1] = FORCE_PULL_AMNT;

        assertEq(address(agent).balance, 0, "agent should have no FIL");

        vm.prank(IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN));
        police.forcePullFundsFromMiners(address(agent), _miners, _amounts);

        assertEq(address(agent).balance, FORCE_PULL_AMNT * 2, "Agent should have 2 times the force pull amount of FIL");
    }

    function testForceMakePayments() public {
        // give the agent enough funcds to get current
        address funder = makeAddr("FUNDER");
        vm.deal(funder, 100e18);

        SignedCredential memory signedCredential = makeAgentOverLeveraged(1e18, 1e18);

        vm.startPrank(funder);
        wFIL.deposit{value: 100e18}();
        wFIL.transfer(address(agent), 100e18);
        vm.stopPrank();

        vm.prank(IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN));
        police.forceMakePayments(address(agent), signedCredential);

        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());

        assertEq(account.epochsPaid, police.windowInfo().deadline, "Agent should have paid up to current epoch");
    }

    function testSetWindowLengthNonAdmin() public {
        uint256 newWindowPeriod = 100;
        try police.setWindowLength(newWindowPeriod) {
            assertTrue(false, "Should have reverted with Unauthorized error");
        } catch (bytes memory err) {
            (,,, string memory reason) = Decode.unauthorizedError(err);
            assertEq(reason, "AgentPolice: Unauthorized");
        }
    }

    function testSetWindowLength() public {
        uint256 newWindowPeriod = 100;
        vm.prank(IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN));
        police.setWindowLength(newWindowPeriod);
        assertEq(police.windowLength(), newWindowPeriod);
    }

    function testTransferOwnershipNonAdmin() public {
        Auth auth = Auth(address(AuthController.getSubAuthority(router, address(police))));
        vm.expectRevert("UNAUTHORIZED");
        auth.transferOwnership(address(this));
        assertEq(auth.owner(), IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN));
    }

    function testTransferOwnership() public {
        address owner = IRouter(router).getRoute(ROUTE_AGENT_POLICE_ADMIN);
        address newOwner = makeAddr("NEW OWNER");
        Auth auth = Auth(address(AuthController.getSubAuthority(router, address(police))));

        vm.prank(owner);
        auth.transferOwnership(newOwner);

        assertEq(auth.owner(), newOwner);
    }

    function testLockoutNonAdmin() public {
        try police.lockout(address(0), address(0)) {
            assertTrue(false, "Should have reverted with Unauthorized error");
        } catch (bytes memory err) {
            (,,, string memory reason) = Decode.unauthorizedError(err);
            assertEq(reason, "AgentPolice: Unauthorized");
        }
    }

    function makeAgentOverPowered(uint256 powerTokenStake, uint256 borrowAmount, uint256 newQAPower) internal returns (
        SignedCredential memory sc
    ) {
        vm.prank(address(agent));
        agent.borrow(borrowAmount, 0, signedCred, powerTokenStake);
        assertEq(wFIL.balanceOf(address(agent)), borrowAmount);
        assertEq(IERC20(powerToken).balanceOf(address(pool)), powerTokenStake);
        uint256 agentPowTokenBal = IERC20(powerToken).balanceOf(address(agent));
        assertEq(agentPowTokenBal, signedCred.vc.miner.qaPower - powerTokenStake);

        sc = issueSC(createCustomCredential(address(agent), newQAPower, 10e18, 5e18, 1e18));

        // no funds get burned here
        police.checkPower(address(agent), sc);

        assertEq(IERC20(address(powerToken)).totalSupply(), signedCred.vc.miner.qaPower);
        assertTrue(police.isOverPowered(address(agent)));
        assertTrue(police.isOverPowered(agent.id()));
    }

    function makeAgentOverLeveraged(uint256 borrowAmount, uint256 powerTokenStake) internal returns (
        SignedCredential memory sc
    ) {
        vm.prank(address(agent));
        agent.borrow(borrowAmount, 0, signedCred, powerTokenStake);

        sc = issueSC(createCustomCredential(
            address(agent),
            10e18,
            // 0 expected daily rewards
            0,
            5e18,
            0
        ));

        police.checkLeverage(address(agent), sc);
        assertTrue(police.isOverLeveraged(agent.id()));
    }
}

contract AgentDefaultTest is BaseTest {
    using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
    address poolOperator = makeAddr("POOL_OPERATOR");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    uint256 stakeAmount;

    IAgent agent;
    MockMiner miner;
    IPool pool1;
    IPool pool2;
    IERC4626 pool46261;
    IERC4626 pool46262;

    SignedCredential signedCred;
    IAgentPolice police;

    address powerToken;

    function setUp() public {
        police = GetRoute.agentPolice(router);
        powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);

        pool1 = createPool(
            "TEST1",
            "TEST1",
            poolOperator,
            2e18
        );
        pool46261 = IERC4626(address(pool1));

        pool2 = createPool(
            "TEST2",
            "TEST2",
            poolOperator,
            2e18
        );
        pool46262 = IERC4626(address(pool2));
        // investor1 stakes 10 FIL
        vm.deal(investor1, 11e18);
        stakeAmount = 5e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount*2}();
        wFIL.approve(address(pool1), stakeAmount);
        wFIL.approve(address(pool2), stakeAmount);
        pool46261.deposit(stakeAmount, investor1);
        pool46262.deposit(stakeAmount, investor1);
        vm.stopPrank();

        (agent, miner) = configureAgent(minerOwner);
        // mint some power for the agent
        signedCred = issueGenericSC(address(agent));
        vm.startPrank(address(agent));
        agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
        IERC20(powerToken).approve(address(pool1), signedCred.vc.miner.qaPower);
        IERC20(powerToken).approve(address(pool2), signedCred.vc.miner.qaPower);

        agent.borrow(stakeAmount / 2, pool1.id(), signedCred, signedCred.vc.miner.qaPower / 2);
        agent.borrow(stakeAmount / 2, pool2.id(), signedCred, signedCred.vc.miner.qaPower / 2);
        vm.stopPrank();
    }

    function testCheckOverLeveraged() public {
        // 0 expected daily rewards
        SignedCredential memory sc = issueSC(createCustomCredential(address(agent), 5e18, 0, 5e18, 4e18));

        police.checkLeverage(address(agent), sc);

        assertTrue(police.isOverLeveraged(address(agent)), "Agent should be over leveraged");
    }

    // in this test, we check default
    // resulting in pools borrowAmounts being written down by the power token weighted agent liquidation value
    function testCheckDefault() public {
        // this credential gives a 1e18 liquidation value, and overleverage / overpowered
        SignedCredential memory sc = issueSC(createCustomCredential(address(agent), 5e18, 0, 5e18, 4e18));

        police.checkDefault(address(agent), sc);

        assertTrue(police.isOverLeveraged(address(agent)), "Agent should be over leveraged");
        assertTrue(police.isOverPowered(address(agent)), "Agent should be over powered");
        assertTrue(police.isInDefault(address(agent)), "Agent should be in default");
        uint256 pool1PostDefaultTotalBorrowed = pool1.totalBorrowed();
        uint256 pool2PostDefaultTotalBorrowed = pool2.totalBorrowed();

        // since _total_ MLV is 1e18, each pool should be be left with 1e18/2
        assertEq(pool1PostDefaultTotalBorrowed, 1e18 / 2, "Wrong write down amount");
        assertEq(pool2PostDefaultTotalBorrowed, 1e18 / 2, "Wrong write down amount");
    }
}

contract AgentCollateralsTest is BaseTest {
     using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
    address poolOperator = makeAddr("POOL_OPERATOR");
    string poolName = "FIRST POOL NAME";
    uint256 baseInterestRate = 20e18;
    uint256 stakeAmount;

    IAgent agent;
    MockMiner miner;
    IPool pool1;
    IPool pool2;
    IERC4626 pool46261;
    IERC4626 pool46262;

    SignedCredential signedCred;
    IAgentPolice police;

    address powerToken;

    uint256 borrowAmount = 10e18;

    function setUp() public {
        police = GetRoute.agentPolice(router);
        powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);

        pool1 = createPool(
            "TEST1",
            "TEST1",
            poolOperator,
            2e18
        );
        pool46261 = IERC4626(address(pool1));

        pool2 = createPool(
            "TEST2",
            "TEST2",
            poolOperator,
            2e18
        );
        pool46262 = IERC4626(address(pool2));
        // investor1 stakes 10 FIL
        vm.deal(investor1, 50e18);
        stakeAmount = 20e18;
        vm.startPrank(investor1);
        wFIL.deposit{value: stakeAmount*2}();
        wFIL.approve(address(pool1), stakeAmount);
        wFIL.approve(address(pool2), stakeAmount);
        pool46261.deposit(stakeAmount, investor1);
        pool46262.deposit(stakeAmount, investor1);
        vm.stopPrank();

        (agent, miner) = configureAgent(minerOwner);
        // mint some power for the agent
        signedCred = issueGenericSC(address(agent));
        vm.startPrank(address(agent));
        agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
        IERC20(powerToken).approve(address(pool1), signedCred.vc.miner.qaPower);
        IERC20(powerToken).approve(address(pool2), signedCred.vc.miner.qaPower);

        agent.borrow(borrowAmount, pool1.id(), signedCred, signedCred.vc.miner.qaPower / 2);
        agent.borrow(borrowAmount, pool2.id(), signedCred, signedCred.vc.miner.qaPower / 2);
        vm.stopPrank();
    }

    function testGetMaxWithdrawUnderLiquidity() public {
        /*
            issue a new signed cred to make Agent's financial situation look like this:
            - qap: 10e18
            - pool 1 borrow amount 10e18
            - pool 2 borrow amount 10e18
            - pool1 power token stake 5e18
            - pool2 power token stake 5e18
            - agent assets: 10e18
            - agent liabilities: 8e18
            - agent liquid balance: 10e18

            the agent should be able to withdraw:
            liquid balance + assets - liabilities - minCollateralValuePool1 - minCollateralValuePool2

            (both pools require 10% of their totalBorrwed amount)
        */

        SignedCredential memory sc = issueSC(createCustomCredential(
            address(agent),
            signedCred.vc.miner.qaPower,
            signedCred.vc.miner.expectedDailyRewards,
            signedCred.vc.miner.assets,
            8e18
        ));

        // expected withdraw amount is the agents liquidation value minus the min collateral of both pools
        uint256 liquidationValue = agent.liquidAssets() + sc.vc.miner.assets - sc.vc.miner.liabilities;
        // the mock pool implementation returns 10% of totalBorrowed for minCollateral
        Account memory account1 = AccountHelpers.getAccount(router, address(agent), pool1.id());
        Account memory account2 = AccountHelpers.getAccount(router, address(agent), pool2.id());

        uint256 minCollateralPool1 = pool1.implementation().minCollateral(account1, sc.vc);
        uint256 minCollateralPool2 = pool2.implementation().minCollateral(account2, sc.vc);
        uint256 expectedWithdrawAmount = liquidationValue - minCollateralPool1 - minCollateralPool2;

        uint256 withdrawAmount = agent.maxWithdraw(sc);
        assertEq(withdrawAmount, expectedWithdrawAmount, "Wrong withdraw amount");
    }

    function testWithdrawUnderMax(uint256 withdrawAmount) public {
        vm.assume(withdrawAmount < agent.maxWithdraw(signedCred));

        address receiver = makeAddr("RECEIVER");

        assertEq(receiver.balance, 0, "Receiver should have no balance");
        vm.prank(address(agent));
        agent.withdrawBalance(receiver, withdrawAmount, signedCred);
        assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
    }

    function testWithdrawrMax() public {
        uint256 withdrawAmount = agent.maxWithdraw(signedCred);

        address receiver = makeAddr("RECEIVER");

        assertEq(receiver.balance, 0, "Receiver should have no balance");
        vm.prank(address(agent));
        agent.withdrawBalance(receiver, withdrawAmount, signedCred);
        assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
    }

    function testWithdrawTooMuch(uint256 overWithdrawAmt) public {
        address receiver = makeAddr("RECEIVER");
        uint256 withdrawAmount = agent.maxWithdraw(signedCred);
        vm.assume(overWithdrawAmt > withdrawAmount);
        vm.prank(address(agent));
        try agent.withdrawBalance(receiver, withdrawAmount * 2, signedCred) {
            assertTrue(false, "Should not be able to withdraw more than the maxwithdraw amount");
        } catch (bytes memory b) {
            (,,,,, string memory reason) = Decode.insufficientCollateralError(b);

            assertEq(reason, "Attempted to draw down too much collateral");
        }
    }

    function testMaxWithdrawToLiquidityLimit() public {
        uint256 LIQUID_AMOUNT = 10000;
        address[] memory _miners = new address[](1);
        uint256[] memory _amounts = new uint256[](1);
        // push funds to the miner so that the agent's liquid balance is less than the withdrawAmount
        _amounts[0] = agent.liquidAssets() - LIQUID_AMOUNT;
        _miners[0] = address(miner);
        vm.startPrank(address(agent));
        agent.pushFundsToMiners(_miners, _amounts);

        uint256 withdrawAmount = agent.maxWithdraw(signedCred);

        assertEq(withdrawAmount, LIQUID_AMOUNT, "max withdraw should be the liquidity limit");
        vm.stopPrank();
    }

    function testRemoveMiner() public {
        address newMiner = _newMiner(minerOwner);
        // add another miner to the agent
        _agentClaimOwnership(address(agent), newMiner, minerOwner);

        // in this example, remove a miner that has no power or assets
        SignedCredential memory minerCred = issueSC(createCustomCredential(
            newMiner,
            0,
            0,
            0,
            0
        ));

        address newMinerOwner = makeAddr("NEW_MINER_OWNER");

        assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
        vm.prank(address(agent));
        agent.removeMiner(newMinerOwner, newMiner, signedCred, minerCred);
        assertEq(agent.hasMiner(newMiner), false, "Miner should be removed");
    }

    function testRemoveMinerWithTooMuchPower(uint256 powerAmount) public {
        vm.assume(powerAmount <= signedCred.vc.miner.qaPower);
        address newMiner = _newMiner(minerOwner);
        // add another miner to the agent
        _agentClaimOwnership(address(agent), newMiner, minerOwner);

        // in this example, remove a miner that contributes all the borrowing power
        SignedCredential memory minerCred = issueSC(createCustomCredential(
            newMiner,
            signedCred.vc.miner.qaPower,
            0,
            0,
            0
        ));

        address newMinerOwner = makeAddr("NEW_MINER_OWNER");

        assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
        vm.prank(address(agent));
        try agent.removeMiner(newMinerOwner, newMiner, signedCred, minerCred) {
            assertTrue(false, "Should not be able to remove a miner with too much power");
        } catch (bytes memory b) {
            (,,,,, string memory reason) = Decode.insufficientCollateralError(b);

            assertEq(reason, "Attempted to remove a miner with too much power");
            assertEq(agent.hasMiner(newMiner), true, "Miner should be removed");
        }
    }

    function testRemoveMinerWithTooLargeLiquidationValue() public {
        address newMiner = _newMiner(minerOwner);
        // add another miner to the agent
        _agentClaimOwnership(address(agent), newMiner, minerOwner);

        // transfer out the balance of the agent to reduce the total collateral of the agent
        address recipient = makeAddr("RECIPIENT");
        uint256 withdrawAmount = agent.maxWithdraw(signedCred);
        vm.prank(address(agent));
        agent.withdrawBalance(recipient, withdrawAmount, signedCred);

        // in this example, remove a miner that contributes all the assets
        SignedCredential memory minerCred = issueSC(createCustomCredential(
            newMiner,
            0,
            0,
            signedCred.vc.miner.assets,
            0
        ));

        address newMinerOwner = makeAddr("NEW_MINER_OWNER");

        assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
        vm.prank(address(agent));
        try agent.removeMiner(newMinerOwner, newMiner, signedCred, minerCred) {
            assertTrue(false, "Should not be able to remove a miner with too much liquidation value");
        } catch (bytes memory b) {
            (,,,,, string memory reason) = Decode.insufficientCollateralError(b);

            assertEq(reason, "Agent does not have enough collateral to remove Miner");
            assertEq(agent.hasMiner(newMiner), true, "Miner should be removed");
        }
    }
}

contract AgentTooManyPoolsTest is BaseTest {
     using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    address poolOperator = makeAddr("POOL_OPERATOR");

    IAgent agent;
    MockMiner miner;

    SignedCredential signedCred;
    IAgentPolice police;

    address powerToken;

    uint256 stakeAmountPerPool = 2e18;
    uint256 borrowAmountPerPool = 1e18;
    uint256 maxPools;
    uint256 powerTokenStakePerPool;

    function setUp() public {
        police = GetRoute.agentPolice(router);
        powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
        // investor1 stakes 10 FIL
        vm.deal(investor1, 50e18);
        vm.prank(investor1);
        wFIL.deposit{value: 50e18}();

        (agent, miner) = configureAgent(minerOwner);
        // mint some power for the agent
        signedCred = issueGenericSC(address(agent));
        vm.prank(address(agent));
        agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
        maxPools = GetRoute.agentPolice(router).maxPoolsPerAgent();
        powerTokenStakePerPool = signedCred.vc.miner.qaPower / (maxPools * 2);

        for (uint256 i = 0; i <= maxPools; i++) {
            string memory poolName = Strings.toString(i);
            IPool _pool = createPool(
                poolName,
                poolName,
                poolOperator,
                2e18
            );

            _deposit(_pool);

            vm.startPrank(address(agent));
            IERC20(powerToken).approve(address(_pool), signedCred.vc.miner.qaPower);
            agent.borrow(
                borrowAmountPerPool,
                _pool.id(),
                signedCred,
                powerTokenStakePerPool
            );
            vm.stopPrank();
        }
    }

    function testTooManyPoolsBorrow() public {
        // create maxPool + 1 pool
        IPool pool = createPool(
            "Too manyith pool",
            "OOPS",
            poolOperator,
            2e18
        );

        _deposit(pool);

        vm.startPrank(address(agent));
        IERC20(powerToken).approve(address(pool), powerTokenStakePerPool);
        try agent.borrow(
            borrowAmountPerPool,
            pool.id(),
            signedCred,
            powerTokenStakePerPool
        ) {
            assertTrue(false, "Agent should not be able to borrow from 11 pools");
        } catch (bytes memory b) {
            (,string memory reason) = Decode.tooManyPoolsError(b);

            assertEq(reason, "Agent: Too many pools");
        }
        vm.stopPrank();
    }

    function _deposit(IPool pool) internal {
        vm.startPrank(investor1);
        wFIL.approve(address(pool), stakeAmountPerPool);
        pool.deposit(stakeAmountPerPool, investor1);
        vm.stopPrank();
    }
}
