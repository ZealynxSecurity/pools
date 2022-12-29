// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Authority} from "src/Auth/Auth.sol";
import {AuthController} from "src/Auth/AuthController.sol";
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

import {ROUTE_AGENT_FACTORY_ADMIN, ROUTE_MINER_REGISTRY} from "src/Constants/Routes.sol";
import {Roles} from "src/Constants/Roles.sol";
import "src/Constants/FuncSigs.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
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
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
    string poolName = "FIRST POOL NAME";
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
        IPoolFactory poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
        pool = createPool(
            "TEST",
            "TEST",
            ZERO_ADDRESS,
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

        Account memory account = pool.getAccount(address(agent));
        assertEq(account.startEpoch, borrowBlock);
        assertGt(account.pmtPerPeriod, 0);
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

        Account memory account = pool.getAccount(address(agent));
        assertEq(account.totalBorrowed, 0);
        assertEq(account.powerTokensStaked, 0);
        assertEq(account.pmtPerPeriod, 0);
    }

    function testPullFundsFromMiners() public {}

    function testPushFundsToMiners() public {}
}

contract AgentPoliceTest is BaseTest {
    address investor1 = makeAddr("INVESTOR_1");
    address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
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
        IPoolFactory poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
        pool = createPool(
            "TEST",
            "TEST",
            ZERO_ADDRESS,
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

    // get a weird error when using expectRevert here:
    // [FAIL. Reason: Error != expected error: NH{q != Agent: Cannot perform action when overpowered]
    function testFailBorrowWhenOverPowered() public {
        uint256 borrowAmount = 0.5e18;
        uint256 powerTokenStake = 7.5e18;
        uint256 newQAPower = 5e18;
        SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

        vm.prank(address(agent));
        agent.borrow(borrowAmount, 0, sc, powerTokenStake);
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
        vm.expectRevert("Agent: Cannot perform action while overpowered");
        vm.startPrank(address(agent));
        agent.removeMiner(address(this), address(miner), signedCred);
    }

    function testForceBurnPowerWhenNotOverPowered() public {
        signedCred = issueGenericSC(address(agent));
        vm.expectRevert("AgentPolice: Agent is not overpowered");
        police.forceBurnPower(address(agent), signedCred);
    }

    // agent does not end up overpowered because the agent has enough power tokens liquid to cover the decrease in real power
    function testForceBurnPowerWithAdequateBal() public {
        uint256 newQAPower = 5e18;

        MinerData memory minerData = MinerData(
            1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, newQAPower, 5e18, 0, 0
        );

        VerifiableCredential memory _vc = VerifiableCredential(
            vcIssuer,
            address(agent),
            block.number,
            block.number + 100,
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
        address[] memory minersToAdd = new address[](1);
        // prepare a second miner to draw funds from
        MockMiner secondMiner = new MockMiner();

        secondMiner.change_owner_address(address(secondMiner), address(agent));
        require(secondMiner.next_owner(address(secondMiner)) == address(agent), "Agent not set as owner");
        minersToAdd[0] = address(secondMiner);

        vm.prank(minerOwner);
        agent.addMiners(minersToAdd);
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
        vm.expectRevert("AgentPolice: Agent is not overleveraged");
        police.forcePullFundsFromMiners(address(agent), _miners, new uint256[](2));
    }

    // TODO: once overLeveraged is implement
    function testForcePullFundsFromMiners() internal {
        address[] memory minersToAdd = new address[](1);
        // prepare a second miner to draw funds from
        MockMiner secondMiner = new MockMiner();

        secondMiner.change_owner_address(address(secondMiner), address(agent));
        require(secondMiner.next_owner(address(secondMiner)) == address(agent), "Agent not set as owner");
        minersToAdd[0] = address(secondMiner);

        vm.prank(minerOwner);
        agent.addMiners(minersToAdd);
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
        police.forcePullFundsFromMiners(address(agent), _miners, new uint256[](2));

        assertEq(address(agent).balance, 3e18);
        assertEq(address(miner).balance, 0);
        assertEq(address(secondMiner).balance, 0);
    }

    function testSetWindowLengthNonAdmin() public {
        uint256 newWindowPeriod = 100;
        vm.expectRevert("AgentPolice: Not authorized");
        police.setWindowLength(newWindowPeriod);
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
        vm.expectRevert("AgentPolice: Not authorized");
        police.lockout(address(this));
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

        MinerData memory minerData = MinerData(
            1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, newQAPower, 5e18, 0, 0
        );

        VerifiableCredential memory _vc = VerifiableCredential(
            vcIssuer,
            address(agent),
            block.number,
            block.number + 100,
            minerData
        );

        sc = issueSC(_vc);

        // no funds get burned here
        police.checkPower(address(agent), sc);

        assertEq(IERC20(address(powerToken)).totalSupply(), signedCred.vc.miner.qaPower);
        assertTrue(police.isOverPowered(address(agent)));
        assertTrue(police.isOverPowered(agent.id()));
    }

    function testMakePayments() public {
        // TODO:
    }
}
