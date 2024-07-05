// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase
pragma solidity 0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BytesLib} from "bytes-utils/BytesLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "test/helpers/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {FinMath} from "src/Pool/FinMath.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {WFIL} from "shim/WFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IMockMiner} from "test/helpers/MockMiner.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {UpgradedAgentDeployer} from "test/helpers/UpgradedAgentDeployer.sol";
import {UpgradedAgent} from "test/helpers/UpgradedAgent.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
import {errorSelector} from "test/helpers/Utils.sol";
import {FlipSig} from "test/helpers/FlipSig.sol";

import "./ProtocolTest.sol";

contract AgentBasicTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    IAgent agent;

    function setUp() public {
        miner = _newMiner(minerOwner1);
        agent = _configureAgent(minerOwner1, miner);
    }

    function assertAgentPermissions(address operator, address owner, address _agent) public {
        assertEq(Agent(payable(_agent)).owner(), owner, "wrong owner");
        assertEq(Agent(payable(_agent)).operator(), operator, "wrong operator");
    }

    function testInitialState() public {
        assertAgentPermissions(minerOwner1, minerOwner1, address(agent));
    }

    function testAddMinerNonOwnerOperator() public {
        SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), miner);
        vm.startPrank(investor1);
        try agent.addMiner(addMinerCred) {
            assertTrue(false, "should have failed - unauthorized");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testAddDuplicateMiner() public {
        // hack to get the miner's next_owner to be the agent again so we can attempt to add duplicate miners without running into other errors
        // although i dont think this situation could ever occur (because agent would already own the miner at this point)
        vm.startPrank(address(agent));
        miner.changeOwnerAddress(address(agent));
        vm.stopPrank();

        SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), miner);

        vm.startPrank(minerOwner1);
        try agent.addMiner(addMinerCred) {
            assertTrue(false, "should have failed - duplicate miner");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), MinerRegistry.InvalidParams.selector);
        }

        vm.stopPrank();
    }

    function testAddTooManyMiners() public {
        uint256 maxMiners = GetRoute.agentPolice(router).maxMiners();
        for (uint256 i = 0; i < maxMiners; i++) {
            _agentClaimOwnership(address(agent), _newMiner(minerOwner1), minerOwner1);
        }

        uint64 _miner = _newMiner(minerOwner1);
        vm.startPrank(minerOwner1);
        _miner.changeOwnerAddress(address(agent));

        SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), _miner);

        vm.expectRevert(IAgentPolice.MaxMinersReached.selector);
        agent.addMiner(addMinerCred);
        vm.stopPrank();
    }

    function testTransferOwner() public {
        address owner = makeAddr("OWNER");
        IAuth authAgent = IAuth(address(agent));
        vm.prank(minerOwner1);
        authAgent.transferOwnership(owner);
        assertEq(authAgent.pendingOwner(), owner);
        vm.prank(owner);
        authAgent.acceptOwnership();
        assertEq(authAgent.owner(), owner);
    }

    function testTransferOperator() public {
        address operator = makeAddr("OPERATOR");
        IAuth authAgent = IAuth(address(agent));
        vm.prank(minerOwner1);
        authAgent.transferOperator(operator);
        assertEq(authAgent.pendingOperator(), operator);
        vm.prank(operator);
        authAgent.acceptOperator();
        assertEq(authAgent.operator(), operator);
    }

    function testSetAdoRequestKey(address pubKey) public {
        vm.startPrank(_agentOwner(agent));
        agent.setAdoRequestKey(pubKey);
        assertEq(agent.adoRequestKey(), pubKey);
    }

    function testReceive() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (IAgent agent1,) = configureAgent(investor1);
        uint256 agentFILBal = address(agent1).balance;

        vm.prank(investor1);
        (bool sent,) = payable(address(agent1)).call{value: transferAmt}("");
        assertTrue(sent);
        assertEq(address(agent1).balance, agentFILBal + transferAmt);
    }

    function testFallback() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (IAgent _agent,) = configureAgent(investor1);
        uint256 agentFILBal = address(_agent).balance;

        vm.prank(investor1);
        (bool sent,) = payable(address(_agent)).call{value: transferAmt}(bytes("fdsa"));
        assertTrue(sent);
        assertEq(address(_agent).balance, agentFILBal + transferAmt);
    }

    function testSingleUseCredentials() public {
        // testing that single use credentials are consumed through pushFunds call
        uint256 pushAmount = 1e18;
        vm.deal(address(agent), pushAmount);
        SignedCredential memory pushFundsCred = issuePushFundsCred(agent.id(), miner, pushAmount);

        vm.startPrank(minerOwner1);
        agent.pushFunds(pushFundsCred);

        try agent.pushFunds(pushFundsCred) {
            assertTrue(false, "should have failed - single use credential");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
        }

        vm.stopPrank();
    }
}

contract AgentPushPullFundsTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    IAgent agent;

    function setUp() public {
        miner = _newMiner(minerOwner1);
        agent = _configureAgent(minerOwner1, miner);
    }

    function testPullFunds(uint256 drawAmount) public {
        vm.assume(drawAmount > 0.001e18);
        uint256 preAgentBal = address(agent).balance;

        address miner1 = idStore.ids(miner);
        // give the miner some funds to pull
        vm.deal(miner1, drawAmount);

        assertEq(wFIL.balanceOf(address(agent)), 0);
        SignedCredential memory pullFundsCred = issuePullFundsCred(agent.id(), miner, drawAmount);
        vm.startPrank(minerOwner1);
        agent.pullFunds(pullFundsCred);
        vm.stopPrank();
        assertEq(address(agent).balance, drawAmount + preAgentBal);
        assertEq(miner1.balance, 0);
    }

    function testPushFunds(uint256 pushAmount) public {
        vm.assume(pushAmount > 0.001e18);
        require(address(agent).balance == 0);

        address miner1 = idStore.ids(miner);
        // give the agent some funds to pull
        vm.deal(address(agent), pushAmount);

        SignedCredential memory pushFundsCred = issuePushFundsCred(agent.id(), miner, pushAmount);
        vm.prank(minerOwner1);
        agent.pushFunds(pushFundsCred);

        assertEq(address(agent).balance, 0);
        assertEq(miner1.balance, pushAmount);
    }

    function testPushFundsToRandomMiner() public {
        uint64 secondMiner = _newMiner(minerOwner1);

        SignedCredential memory pushFundsCred = issuePushFundsCred(agent.id(), secondMiner, 1e18);
        vm.startPrank(minerOwner1);
        try agent.pushFunds(pushFundsCred) {
            assertTrue(false, "should not be able to push funds to random miners");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), Unauthorized.selector);
        }

        vm.stopPrank();
    }

    function testPullFundsWithWrongCred() public {
        SignedCredential memory pullFundsCred = issuePullFundsCred(agent.id(), miner, 0);
        vm.startPrank(minerOwner1);
        try agent.pushFunds(pullFundsCred) {
            assertTrue(false, "should not be able to pull funds with wrong cred");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), VCVerifier.InvalidCredential.selector);
        }
    }

    function testPushFundsWithWrongCred() public {
        SignedCredential memory pullFundsCred = issuePushFundsCred(agent.id(), miner, 0);
        vm.startPrank(minerOwner1);
        try agent.pullFunds(pullFundsCred) {
            assertTrue(false, "should not be able to pull funds with wrong cred");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), VCVerifier.InvalidCredential.selector);
        }
    }
}

contract AgentPoliceApprovalTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");

    IAgent agent;
    uint64 miner;
    IAgentPolice agentPolice;

    function setUp() public {
        (agent, miner) = configureAgent(minerOwner);
        agentPolice = GetRoute.agentPolice(router);
    }

    function testPositionAfterBorrow(
        uint256 existingPrincipal,
        uint256 newPrincipal,
        uint256 liquidationValue,
        uint256 epochsForward,
        uint256 agentTotalValue,
        uint256 borrowDTL
    ) public {
        existingPrincipal = bound(existingPrincipal, 0, MAX_FIL);
        newPrincipal = bound(newPrincipal, 0, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        epochsForward = bound(epochsForward, 0, EPOCHS_IN_YEAR);
        agentTotalValue = bound(agentTotalValue, 0, MAX_FIL);
        // between 1% and 100%
        borrowDTL = bound(borrowDTL, 1e16, 1e18);

        vm.prank(systemAdmin);
        agentPolice.setBorrowDTL(borrowDTL);

        vm.deal(address(agent), agentTotalValue);

        vm.startPrank(address(pool));
        // set the account in storage with the right amount of principal
        IRouter(router).setAccount(
            agent.id(), 0, Account(block.number, existingPrincipal + newPrincipal, block.number, false)
        );
        vm.stopPrank();

        vm.roll(block.number + epochsForward);

        AgentData memory agentData = createAgentData(liquidationValue);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent.id(),
            block.number,
            block.number + 100,
            newPrincipal,
            IAgent.borrow.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        vm.startPrank(address(agent));
        if (liquidationValue > agentTotalValue) {
            vm.expectRevert(IAgentPolice.LiquidationValueTooHigh.selector);
            agentPolice.agentApproved(vc);
            return;
        }

        if (liquidationValue == 0) {
            vm.expectRevert(IAgentPolice.OverLimitDTL.selector);
            agentPolice.agentApproved(vc);
            return;
        }

        uint256 debt = FinMath.computeDebt(AccountHelpers.getAccount(router, agent.id(), 0), pool.getRate());
        uint256 dtl = debt.divWadDown(liquidationValue);
        if (dtl > agentPolice.borrowDTL()) {
            vm.expectRevert(IAgentPolice.OverLimitDTL.selector);
            agentPolice.agentApproved(vc);
            return;
        }

        // should not fail
        try agentPolice.agentApproved(vc) {
            assertTrue(true, "should not have failed");
        } catch {
            assertTrue(false, "should not have failed");
        }
    }

    function testPositionBeforeWithdraw(
        uint256 existingPrincipal,
        uint256 liquidationValue,
        uint256 epochsForward,
        uint256 agentTotalValue,
        uint256 withdrawAmount,
        uint256 borrowDTL
    ) public {
        existingPrincipal = bound(existingPrincipal, 0, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        epochsForward = bound(epochsForward, 0, EPOCHS_IN_YEAR);
        agentTotalValue = bound(agentTotalValue, 0, MAX_FIL);
        // withdraw amount cannot be 0
        withdrawAmount = bound(withdrawAmount, 1, MAX_FIL);
        // between 1% and 100%
        borrowDTL = bound(borrowDTL, 1e16, 1e18);

        vm.prank(systemAdmin);
        agentPolice.setBorrowDTL(borrowDTL);

        vm.deal(address(agent), agentTotalValue);

        vm.startPrank(address(pool));
        // set the account in storage with the right amount of principal
        IRouter(router).setAccount(agent.id(), 0, Account(block.number, existingPrincipal, block.number, false));
        vm.stopPrank();

        vm.roll(block.number + epochsForward);

        AgentData memory agentData = createAgentData(liquidationValue);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent.id(),
            block.number,
            block.number + 100,
            withdrawAmount,
            IAgent.withdraw.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        _assertConfirmRmEquity(existingPrincipal, withdrawAmount, agentTotalValue, liquidationValue, vc);
    }

    function testPositionBeforeRmMiner(
        uint256 existingPrincipal,
        uint256 liquidationValue,
        uint256 epochsForward,
        uint256 agentTotalValue,
        uint256 minerEquityVal,
        uint256 borrowDTL
    ) public {
        existingPrincipal = bound(existingPrincipal, 0, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        epochsForward = bound(epochsForward, 0, EPOCHS_IN_YEAR);
        agentTotalValue = bound(agentTotalValue, 0, MAX_FIL);
        // withdraw amount cannot be 0
        minerEquityVal = bound(minerEquityVal, 1, MAX_FIL);
        // between 1% and 100%
        borrowDTL = bound(borrowDTL, 1e16, 1e18);

        vm.prank(systemAdmin);
        agentPolice.setBorrowDTL(borrowDTL);

        vm.deal(address(agent), agentTotalValue);

        vm.startPrank(address(pool));
        // set the account in storage with the right amount of principal
        IRouter(router).setAccount(agent.id(), 0, Account(block.number, existingPrincipal, block.number, false));
        vm.stopPrank();

        vm.roll(block.number + epochsForward);

        AgentData memory agentData = createAgentData(liquidationValue);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent.id(),
            block.number,
            block.number + 100,
            minerEquityVal,
            IAgent.removeMiner.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        _assertConfirmRmEquity(existingPrincipal, minerEquityVal, agentTotalValue, liquidationValue, vc);
    }

    function _assertConfirmRmEquity(
        uint256 existingPrincipal,
        uint256 withdrawAmount,
        uint256 agentTotalValue,
        uint256 liquidationValue,
        VerifiableCredential memory vc
    ) internal {
        vm.startPrank(address(agent));
        if (existingPrincipal == 0) {
            // this call should not revert
            agentPolice.confirmRmEquity(vc);
            return;
        }

        if (liquidationValue + withdrawAmount > agentTotalValue) {
            vm.expectRevert(IAgentPolice.LiquidationValueTooHigh.selector);
            agentPolice.confirmRmEquity(vc);
            return;
        }

        if (liquidationValue == 0) {
            vm.expectRevert(IAgentPolice.OverLimitDTL.selector);
            agentPolice.confirmRmEquity(vc);
            return;
        }

        uint256 debt = FinMath.computeDebt(AccountHelpers.getAccount(router, agent.id(), 0), pool.getRate());
        uint256 dtl = debt.divWadDown(liquidationValue);
        if (dtl > agentPolice.borrowDTL()) {
            vm.expectRevert(IAgentPolice.OverLimitDTL.selector);
            agentPolice.confirmRmEquity(vc);
            return;
        }

        // should not fail
        try agentPolice.confirmRmEquity(vc) {
            assertTrue(true, "should not have failed");
        } catch {
            assertTrue(false, "should not have failed");
        }
    }
}

contract AgentRmEquityTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = MAX_FIL;

    IAgent agent;
    uint64 miner;
    IAgentPolice agentPolice;

    function setUp() public {
        _depositFundsIntoPool(depositAmt, investor1);
        (agent, miner) = configureAgent(minerOwner);
        agentPolice = GetRoute.agentPolice(router);
    }

    // no matter what statistics come in the credential, if no loans, can withdraw
    function testWithdrawWithNoLoans(uint256 bal, uint256 withdrawAmount) public {
        vm.assume(bal >= withdrawAmount);

        vm.deal(address(agent), withdrawAmount);

        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            // withdraw amount doesn't matter in this test
            withdrawAmount,
            // principal has to be 0 for this test (no loans)
            0,
            // agent value
            bal,
            // collateral value
            bal
        );

        withdrawAndAssert(receiver, withdrawAmount, withdrawCred);
    }

    /// @dev this test only checks against the AgentPolice DTE check, it does not check against the pool's checks
    function testWithdrawWithOutstandingPrincipal(
        uint256 withdrawAmount,
        uint256 principal,
        uint256 liquidationValue,
        uint256 agentValue
    ) public {
        // make sure to have at least 1 FIL worth of principal
        principal = bound(principal, WAD, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        // agentValue includes principal, so it should never be less than principal
        agentValue = bound(agentValue, liquidationValue, MAX_FIL);
        // cannot withdraw more than the balance on agent
        withdrawAmount = bound(withdrawAmount, 0, agentValue);

        agentBorrow(agent, issueGenericBorrowCred(agent.id(), principal));

        (address receiver, SignedCredential memory withdrawCred) =
            customWithdrawCred(withdrawAmount, principal, agentValue, liquidationValue);

        withdrawAndAssert(receiver, withdrawAmount, withdrawCred);
    }

    function testWithdrawIntoUnapprovedDTL(uint256 principal, uint256 liquidationValue) public {
        liquidationValue = bound(liquidationValue, 2e18, MAX_FIL);
        principal = bound(principal, liquidationValue.mulWadUp(agentPolice.borrowDTL() + 1), MAX_FIL * 2);
        uint256 withdrawAmt = principal;
        _depositFundsIntoPool(principal, investor1);
        agentBorrow(agent, issueGenericBorrowCred(agent.id(), principal));
        // create a withdraw credential
        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            withdrawAmt,
            principal,
            // agent value should be big number so DTE does not interfere in this test
            principal * 10,
            liquidationValue
        );

        withdrawAndAssertRevert(receiver, withdrawCred, IAgentPolice.OverLimitDTL.selector);
    }

    function testWithdrawMoreThanLiquid(uint256 bal, uint256 withdrawAmount) public {
        bal = bound(bal, 0, MAX_FIL);
        withdrawAmount = bound(withdrawAmount, bal + 1, MAX_FIL * 2);

        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            withdrawAmount,
            // principal can be 0 as to not half the withdraw,
            0,
            bal,
            bal
        );

        withdrawAndAssertRevert(receiver, withdrawCred, Agent.InsufficientFunds.selector);
    }

    // no matter what statistics come in the credential, if no loans, can remove miner
    function testRemoveMinerWithNoLoans() public {
        (uint64 newMinerOwner, SignedCredential memory removeMinerCred) = customRemoveMinerCred(
            // balance doesn't matter in this test
            miner,
            // principal has to be 0 for this test (no loans)
            0,
            // agent value does not matter for this test
            DUST,
            // collateral value does not matter for this test
            DUST
        );

        removeMinerAndAssert(miner, newMinerOwner, removeMinerCred);
    }

    /// @dev this test only checks against the AgentPolice DTE check
    function testRemoveMinerWithOutstandingPrincipal(uint256 principal, uint256 liquidationValue, uint256 agentValue)
        public
    {
        principal = bound(principal, WAD, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        // agentValue includes principal, so it should never be less than principal
        agentValue = bound(agentValue, liquidationValue, MAX_FIL);

        agentBorrow(agent, issueGenericBorrowCred(agent.id(), principal));

        (uint64 newMinerOwner, SignedCredential memory removeMinerCred) =
            customRemoveMinerCred(miner, principal, agentValue, liquidationValue);

        removeMinerAndAssert(miner, newMinerOwner, removeMinerCred);
    }

    function customWithdrawCred(uint256 withdrawAmount, uint256 principal, uint256 agentValue, uint256 liquidationValue)
        internal
        returns (address receiver, SignedCredential memory sc)
    {
        receiver = makeAddr("RECEIVER");
        vm.deal(address(agent), agentValue);

        AgentData memory agentData = AgentData(
            agentValue,
            liquidationValue,
            // no expected daily faults
            0,
            // edr no longer matters
            0,
            // GCRED deprecated
            0,
            10e18,
            principal,
            0,
            0,
            0
        );

        sc = issueWithdrawCred(agent.id(), withdrawAmount, agentData);
    }

    function customRemoveMinerCred(uint64 minerToRemove, uint256 principal, uint256 agentValue, uint256 collateralValue)
        internal
        returns (uint64 newMinerOwnerId, SignedCredential memory rmMinerCred)
    {
        address newMinerOwner = makeAddr("NEW_MINER_OWNER");

        newMinerOwnerId = idStore.addAddr(newMinerOwner);

        AgentData memory agentData = AgentData(
            agentValue,
            collateralValue,
            // no expected daily faults
            0,
            0,
            // GCRED deprecated
            0,
            10e18,
            principal,
            0,
            0,
            0
        );

        rmMinerCred = issueRemoveMinerCred(agent.id(), minerToRemove, agentData);
    }

    function withdrawAndAssert(address receiver, uint256 withdrawAmount, SignedCredential memory withdrawCred)
        internal
    {
        _fundAgentsMiners(agent, withdrawCred.vc);

        uint256 preAgentLiquidFunds = agent.liquidAssets();

        testInvariants("withdrawAndAssertSuccess - pre");

        bool shouldBeAllowed;
        bytes memory errorBytes;

        // we expect the agent to follow the agent police's logic, we test the agent police logic elsewhere
        // this needs to be called from the agent
        vm.startPrank(address(agent));
        try agentPolice.confirmRmEquity(withdrawCred.vc) {
            shouldBeAllowed = true;
        } catch (bytes memory b) {
            shouldBeAllowed = false;
            errorBytes = b;
        }
        vm.stopPrank();

        // if the agent does not have liquid funds, the withdrawal will get stopped on insufficient funds
        if (shouldBeAllowed && agent.liquidAssets() < withdrawCred.vc.value) {
            shouldBeAllowed = false;
            errorBytes = BytesLib.slice(abi.encode(Agent.InsufficientFunds.selector), 0, 4);
        }

        vm.startPrank(minerOwner);
        if (shouldBeAllowed) {
            agent.withdraw(receiver, withdrawCred);

            assertEq(agent.liquidAssets(), preAgentLiquidFunds - withdrawAmount);
            assertEq(receiver.balance, withdrawAmount);
        } else {
            withdrawAndAssertRevert(receiver, withdrawCred, errorSelector(errorBytes));
        }

        testInvariants("withdrawAndAssertSuccess - post");
        vm.stopPrank();
    }

    function withdrawAndAssertRevert(address receiver, SignedCredential memory withdrawCred, bytes4 errorSelectorValue)
        internal
    {
        uint256 preAgentLiquidFunds = agent.liquidAssets();
        // withdraw
        vm.startPrank(minerOwner);
        vm.expectRevert(abi.encodeWithSelector(errorSelectorValue));
        agent.withdraw(receiver, withdrawCred);
        vm.stopPrank();

        assertEq(agent.liquidAssets(), preAgentLiquidFunds, "No funds should have been withdrawn");
        testInvariants("withdrawAndAssertRevert");
    }

    function removeMinerAndAssert(uint64 removedMiner, uint64 newMinerOwner, SignedCredential memory rmMinerCred)
        internal
    {
        _fundAgentsMiners(agent, rmMinerCred.vc);
        uint256 preAgentMinersCount = GetRoute.minerRegistry(router).minersCount(agent.id());

        testInvariants("removeMinerAndAssert - pre");

        bool shouldBeAllowed;
        bytes memory errorBytes;
        // we expect the agent to follow the agent police's logic, we test the agent police logic elsewhere
        // confirmRmEquity needs to be called from the agent
        vm.startPrank(address(agent));
        try agentPolice.confirmRmEquity(rmMinerCred.vc) {
            shouldBeAllowed = true;
        } catch (bytes memory b) {
            shouldBeAllowed = false;
            errorBytes = b;
        }
        vm.stopPrank();

        vm.startPrank(minerOwner);
        if (shouldBeAllowed) {
            agent.removeMiner(newMinerOwner, rmMinerCred);
            assertEq(
                GetRoute.minerRegistry(router).minersCount(agent.id()),
                preAgentMinersCount - 1,
                "Agent should have no miners registered"
            );
            assertFalse(
                GetRoute.minerRegistry(router).minerRegistered(agent.id(), miner),
                "Miner should not be registered after removing"
            );
            assertEq(
                IMockMiner(idStore.ids(removedMiner)).proposed(),
                idStore.ids(newMinerOwner),
                "Miner should have new proposed owner"
            );
        } else {
            vm.expectRevert(errorBytes);
            agent.removeMiner(newMinerOwner, rmMinerCred);

            assertEq(
                GetRoute.minerRegistry(router).minersCount(agent.id()),
                preAgentMinersCount,
                "Agent should have no miners removed"
            );
            assertTrue(
                GetRoute.minerRegistry(router).minerRegistered(agent.id(), miner),
                "Miner should be registered after removing"
            );
            assertEq(
                IMockMiner(idStore.ids(removedMiner)).proposed(),
                idStore.ids(0),
                "Miner should not have new proposed owner"
            );
        }

        testInvariants("removeMinerAndAssertSuccess");
        vm.stopPrank();
    }

    function removeMinerAndAssertRevert(
        uint64 removedMiner,
        uint64 newMinerOwner,
        SignedCredential memory rmMinerCred,
        bytes4 errorSelectorValue
    ) internal {
        vm.startPrank(minerOwner);
        vm.expectRevert(abi.encodeWithSelector(errorSelectorValue));
        agent.removeMiner(newMinerOwner, rmMinerCred);
        vm.stopPrank();

        assertEq(GetRoute.minerRegistry(router).minersCount(agent.id()), 1, "Agent should have 1 miner registered");
        assertTrue(GetRoute.minerRegistry(router).minerRegistered(agent.id(), miner), "Miner should be registered");
        assertEq(
            IMockMiner(idStore.ids(removedMiner)).proposed(), address(0), "Miner should not have new propsed owner"
        );
        testInvariants("removeMinerAndAssertRevert");
    }
}

contract AgentBorrowingTest is ProtocolTest {
    using FixedPointMathLib for uint256;
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = 1000e18;

    IAgent agent;
    uint64 miner;

    function setUp() public {
        _depositFundsIntoPool(depositAmt, investor1);
        (agent, miner) = configureAgent(minerOwner);
    }

    function testBorrowValid(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, depositAmt);
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, borrowCred);
    }

    function testBorrowTwice(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, depositAmt / 2);

        SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);

        uint256 borrowBlock = block.number;
        agentBorrow(agent, borrowCred);
        // roll forward to test the startEpoch and epochsPaid
        vm.roll(block.number + 1000);

        borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);
        // Since we've already borrowed, we pretend the SP locks substantially more funds
        uint256 collateralValue = borrowAmount * 4;

        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());

        AgentData memory agentData = createAgentData(collateralValue);

        uint256 interestOwed = pool.getAgentInterestOwed(agent.id());

        borrowCred.vc.claim = abi.encode(agentData);
        borrowCred = signCred(borrowCred.vc);
        agentBorrow(agent, borrowCred);

        Account memory updatedAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());
        assertEq(updatedAccount.principal, borrowAmount * 2);
        assertEq(updatedAccount.startEpoch, borrowBlock);

        uint256 expectedInterestOwedPerEpoch = updatedAccount.principal.mulWadUp(pool.getRate());
        // if the new interest per epoch is bigger than the previous interest owed, then the epoch cursor should represent 1 epoch of interest worth of interest
        if (expectedInterestOwedPerEpoch > interestOwed * WAD) {
            assertEq(
                updatedAccount.epochsPaid,
                block.number - 1,
                "Agent interest owed should equal the expected interest owed per epoch"
            );
            assertEq(
                pool.getAgentInterestOwed(agent.id()),
                // we expect the interest owed to be the expected interest owed per epoch, div out the extra epoch precision
                expectedInterestOwedPerEpoch.mulWadUp(1),
                "Agent interest owed should equal the expected interest owed per epoch"
            );
        } else {
            // else the epochsPaid should shift forward and the interest should remain unchanged

            assertGt(
                updatedAccount.epochsPaid,
                account.epochsPaid,
                "Account epochs paid should be greater than initial epochs paid after borrowing with interest owed"
            );

            assertTrue(pool.getAgentInterestOwed(agent.id()) >= interestOwed, "Interest owed should not decrease");
            // interest owed should not have changed (using relative approximation )
            assertApproxEqRel(
                pool.getAgentInterestOwed(agent.id()), interestOwed, 1e16, "Interest owed should not have changed"
            );
        }

        testInvariants("testBorrowTwice");
    }

    function testBorrowMoreThanLiquid(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, depositAmt + 1, MAX_FIL);

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        vm.startPrank(minerOwner);
        try agent.borrow(pool.id(), borrowCred) {
            assertTrue(false, "should not be able to borrow more than liquid");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), InsufficientLiquidity.selector);
        }

        vm.stopPrank();
        testInvariants("testBorrowMoreThanLiquid");
    }

    function testBorrowNothing() public {
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), 0);

        vm.startPrank(minerOwner);
        try agent.borrow(pool.id(), borrowCred) {
            assertTrue(false, "should not be able to borrow 0");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), InvalidParams.selector);
        }

        vm.stopPrank();
        testInvariants("testBorrowNothing");
    }

    function testBorrowNonOwnerOperator() public {
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), 1e18);

        vm.startPrank(makeAddr("NON_OWNER_OPERATOR"));
        try agent.borrow(pool.id(), borrowCred) {
            assertTrue(false, "should not be able to borrow more than liquid");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), Unauthorized.selector);
        }

        vm.stopPrank();
        testInvariants("testBorrowNonOwnerOperator");
    }

    function testBorrowWrongCred() public {
        SignedCredential memory nonBorrowCred = issueAddMinerCred(agent.id(), 0);

        vm.startPrank(minerOwner);
        try agent.borrow(pool.id(), nonBorrowCred) {
            assertTrue(false, "should not be able to borrow more than liquid");
        } catch (bytes memory b) {
            assertEq(errorSelector(b), InvalidCredential.selector);
        }

        vm.stopPrank();
        testInvariants("testBorrowWrongCred");
    }
}

contract AgentPayTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    error AccountDNE();

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = 1000e18;

    IAgent agent;
    uint64 miner;

    function setUp() public {
        _depositFundsIntoPool(depositAmt, investor1);
        (agent, miner) = configureAgent(minerOwner);
    }

    function testNonAgentCannotPay(string memory payerSeed) public {
        // Establish Static Params
        uint256 borrowAmount = 10e18;
        uint256 poolId = pool.id();
        uint256 agentId = agent.id();
        uint256 rollFwdAmt = EPOCHS_IN_WEEK * 2;
        SignedCredential memory borrowCred = issueGenericBorrowCred(agentId, borrowAmount);

        // We're just going to use the full amount of interest owed as our pay amount
        (uint256 payAmount,) = calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());
        // Set fuzzed values to logical test limits - in this case anyone but the agent should be unauthorized
        address payer = makeAddr(payerSeed);
        vm.assume(payer != address(agent));
        // Set up the test state

        // Borrow funds and roll forward to generate interest
        agentBorrow(agent, borrowCred);
        vm.roll(block.number + rollFwdAmt);

        // Load the payer with sufficient funds to make the payment
        vm.startPrank(payer);
        vm.deal(payer, payAmount);
        wFIL.deposit{value: payAmount}();
        wFIL.approve(address(pool), payAmount);

        // Attempt to pay the interest - we should revert as unauthorized since the payer is not the agent
        SignedCredential memory payCred = issueGenericPayCred(agentId, payAmount);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.pay(poolId, payCred);
        vm.stopPrank();
        testInvariants("testNonAgentCannotPay");
    }

    function testCannotPayOnNonExistentAccount() public {
        // Establish Static Params
        uint256 payAmount = 10e18;
        uint256 poolId = pool.id();
        uint256 agentId = agent.id();

        // Load the payer with sufficient funds to make the payment
        vm.startPrank(address(agent));
        vm.deal(address(agent), payAmount);
        wFIL.deposit{value: payAmount}();
        wFIL.approve(address(pool), payAmount);
        vm.stopPrank();

        vm.startPrank(address(minerOwner));
        // Attempt to pay the interest - we should revert since the account does not exist
        SignedCredential memory payCred = issueGenericPayCred(agentId, payAmount);
        vm.expectRevert(abi.encodeWithSelector(AccountDNE.selector));
        agent.pay(poolId, payCred);
        vm.stopPrank();
        testInvariants("testCannotPayOnNonExistentAccount");
    }

    function testPayInterestOnly(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_YEAR * 3);
        depositAmt = MAX_FIL;
        _depositFundsIntoPool(depositAmt, minerOwner);
        borrowAmount = bound(borrowAmount, 1e18, MAX_FIL);

        SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);
        (uint256 interestOwed, uint256 interestOwedPerEpoch) =
            calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());

        if (interestOwed + DUST > interestOwedPerEpoch) {
            payAmount = interestOwed;
        } else {
            payAmount = bound(payAmount, interestOwedPerEpoch + DUST, interestOwed - DUST);
        }
        // bind the pay amount to less than the interest owed
        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, borrowCred, payAmount, rollFwdAmt);

        assertEq(
            prePayState.agentBorrowed,
            AccountHelpers.getAccount(router, agent.id(), pool.id()).principal,
            "principal should not change"
        );
        testInvariants("testPayInterestOnly");
    }

    function testPayInterestAndPartialPrincipal(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_WEEK * 3);
        // bind borrow amount min 1e18 to ensure theres a decent amount of principal to repay
        borrowAmount = bound(borrowAmount, 1e18, depositAmt);

        SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);

        (uint256 interestOwed,) = calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());
        // bind the pay amount to in between the interest owed and less than the principal
        payAmount = bound(payAmount, interestOwed + DUST, interestOwed + borrowAmount - DUST);

        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, borrowCred, payAmount, rollFwdAmt);

        uint256 principalPaid = payAmount - interestOwed;

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

        assertEq(
            prePayState.agentBorrowed - principalPaid,
            postPaymentAccount.principal,
            "account should have decreased principal"
        );
        assertEq(postPaymentAccount.epochsPaid, block.number, "epochs paid should be current");
        testInvariants("testPayInterestAndPartialPrincipal");
    }

    function testPayFullExit(uint256 payAmount) public {}

    function testPayTooMuch(uint256 payAmount) public {}

    function borrowRollFwdAndPay(
        IAgent _agent,
        SignedCredential memory borrowCred,
        uint256 payAmount,
        uint256 rollFwdAmt
    ) internal returns (StateSnapshot memory) {
        uint256 agentID = _agent.id();
        agentBorrow(_agent, borrowCred);

        vm.roll(block.number + rollFwdAmt);

        (, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState) =
            agentPay(_agent, _issueGenericPayCred(agentID, payAmount));

        assertPmtSuccess(_agent, prePayState, payAmount, principalPaid, refund);

        return prePayState;
    }

    function assertPmtSuccess(
        IAgent newAgent,
        StateSnapshot memory prePayState,
        uint256 payAmount,
        uint256 principalPaid,
        uint256 refund
    ) internal {
        assertEq(
            prePayState.poolBalanceWFIL + payAmount, wFIL.balanceOf(address(pool)), "pool should have received funds"
        );
        assertEq(
            prePayState.agentBalanceWFIL - payAmount, wFIL.balanceOf(address(newAgent)), "agent should have paid funds"
        );

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, newAgent.id(), pool.id());

        // full exit
        if (principalPaid >= prePayState.agentBorrowed) {
            // refund should be greater than 0 if too much principal was paid
            if (principalPaid > prePayState.agentBorrowed) {
                assertEq(principalPaid - refund, prePayState.agentBorrowed, "should be a refund");
            }

            assertEq(postPaymentAccount.principal, 0, "principal should be 0");
            assertEq(postPaymentAccount.epochsPaid, 0, "epochs paid should be reset");
            assertEq(postPaymentAccount.startEpoch, 0, "start epoch should be reset");
        } else {
            // partial exit or interest only payment
            assertGt(
                postPaymentAccount.epochsPaid, prePayState.accountEpochsPaid, "epochs paid should have moved forward"
            );
            assertLe(postPaymentAccount.epochsPaid, block.number, "epochs paid should not be in the future");
        }
        testInvariants("assertPaySuccess");
    }
}

contract AgentPoliceTest is ProtocolTest {
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    error AlreadyDefaulted();

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    address administration = makeAddr("ADMINISTRATION");
    address liquidator = makeAddr("LIQUIDATOR");

    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IAgentPolice police;
    address policeOwner;

    function setUp() public {
        _depositFundsIntoPool(stakeAmount, investor1);
        (agent, miner) = configureAgent(minerOwner);
        police = GetRoute.agentPolice(router);
        policeOwner = IAuth(address(police)).owner();
    }

    function testBurnSomeoneElseCredential() public {
        // different agent ID
        SignedCredential memory sc = issueGenericBorrowCred(2, WAD);
        vm.startPrank(address(agent));
        vm.expectRevert(Unauthorized.selector);
        police.registerCredentialUseBlock(sc);
    }

    function testReplaySignature() public {
        SignedCredential memory sc = issueGenericBorrowCred(agent.id(), WAD);
        agentBorrow(agent, sc);

        FlipSig flipSig = new FlipSig();

        (uint8 flippedV, bytes32 flippedR, bytes32 flippedS) = flipSig.reuseSignature(sc.v, sc.r, sc.s);

        SignedCredential memory replayedCred = SignedCredential(sc.vc, flippedV, flippedR, flippedS);

        vm.startPrank(minerOwner);
        uint256 poolID = pool.id();
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, flippedS));
        agent.borrow(poolID, replayedCred);

        vm.stopPrank();
    }

    function testPutAgentOnAdministration(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, stakeAmount);
        // helper includes assertions
        putAgentOnAdministration(agent, administration, EPOCHS_IN_DAY, borrowAmount);
        testInvariants("testPutAgentOnAdministration");
    }

    function testPutAgentOnAdministrationNoLoans() public {
        vm.startPrank(IAuth(address(police)).owner());
        try police.putAgentOnAdministration(
            address(agent), issueGenericPutOnAdministrationCred(agent.id(), 1e18), administration
        ) {
            assertTrue(false, "Agent should not be eligible for administration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
        testInvariants("testPutAgentOnAdministrationNoLoans");
    }

    function testInvalidPutAgentOnAdministration() public {
        uint256 borrowAmount = WAD;

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, borrowCred);

        // cv > principal so DTL is in good standing
        uint256 principal = 1e18;
        uint256 collateralValue = 10e18;

        AgentData memory ad = AgentData(
            1e18,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            0,
            0,
            // qaPower hardcoded
            0,
            principal,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent.id(),
            block.number,
            block.number + 100,
            0,
            IAgentPolice.putAgentOnAdministration.selector,
            // minerID irrelevant for setDefault action
            0,
            abi.encode(ad)
        );

        SignedCredential memory sc = signCred(vc);

        vm.startPrank(IAuth(address(police)).owner());
        try police.putAgentOnAdministration(
            // use credential with 0 borrow amount, DTL should be 0
            address(agent),
            sc,
            administration
        ) {
            assertTrue(false, "Agent should not be eligible for administration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testRmAgentFromAdministration() public {
        uint256 rollFwdPeriod = EPOCHS_IN_WEEK;
        uint256 borrowAmount = WAD;

        putAgentOnAdministration(agent, administration, rollFwdPeriod, borrowAmount);

        // deal enough funds to the Agent so it can make a payment back to the Pool
        vm.deal(address(agent), borrowAmount * 4);

        SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

        // here we are exiting the pool by overpaying so much
        (uint256 epochsPaid,,,) = agentPay(agent, sc);

        require(epochsPaid == 0, "Should have exited from the pool");

        sc = issueGenericRecoverCred(agent.id(), 0, 1e18);
        // check that the agent is no longer on administration
        vm.startPrank(IAuth(address(agent)).owner());
        agent.setRecovered(sc);
        vm.stopPrank();

        assertEq(agent.administration(), address(0), "Agent Should not be on administration after paying up");
        testInvariants("testRmAgentFromAdministration");
    }

    function testSetAgentDefaulted() public {
        // helper includes assertions
        setAgentDefaulted(agent, 1e18);
    }

    function testSetAdministrationNonAgentPolice() public {
        uint256 borrowAmount = WAD;
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
        agentBorrow(agent, borrowCred);

        vm.roll(block.number + EPOCHS_IN_WEEK);

        try police.putAgentOnAdministration(
            address(agent), issueGenericPutOnAdministrationCred(agent.id(), 1e18), administration
        ) {
            assertTrue(false, "only agent police owner should be able to call putAgentOnAdministration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }

        try agent.setAdministration(administration) {
            assertTrue(false, "only agent police should be able to put the agent on adminstration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testSetAgentDefaultedNonAgentPolice() public {
        try police.setAgentDefaultDTL(address(agent), issueGenericSetDefaultCred(agent.id(), 1e18)) {
            assertTrue(false, "only agent police owner operator should be able to call setAgentInDefault");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }

        try agent.setInDefault() {
            assertTrue(false, "only agent police should be able to call setAgentInDefault on the agent");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testPrepareMinerForLiquidation() public {
        setAgentDefaulted(agent, 1e18);

        address terminator = makeAddr("liquidator");
        uint64 liquidatorID = idStore.addAddr(terminator);

        vm.startPrank(policeOwner);
        police.prepareMinerForLiquidation(address(agent), miner, liquidatorID);
        vm.stopPrank();
        // get the miner actor to ensure that the proposed owner on the miner is the policeOwner
        assertEq(
            IMockMiner(idStore.ids(miner)).proposed(),
            terminator,
            "Mock miner should have terminator as its proposed owner"
        );
        testInvariants("testPrepareMinerForLiquidation");
    }

    function testDistributeLiquidatedFundsNonAgentPolice() public {
        setAgentDefaulted(agent, 1e18);

        address prankster = makeAddr("prankster");
        vm.startPrank(prankster);
        vm.expectRevert(Unauthorized.selector);
        police.distributeLiquidatedFunds(address(agent), 0);
        testInvariants("testDistributeLiquidatedFundsNonAgentPolice");
    }

    function testDistributeLiquidatedFundsPartialRecoveryNoInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD + 1, stakeAmount);
        recoveredFunds = bound(recoveredFunds, WAD, borrowAmount - 1);

        setAgentDefaulted(agent, borrowAmount);

        uint256 totalAssetsBefore = pool.totalAssets();

        vm.deal(policeOwner, recoveredFunds);
        vm.startPrank(policeOwner);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);

        assertPegInTact();
        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();

        uint256 lostAmount = totalAssetsBefore - totalAssetsAfter;
        uint256 recoverPercent = (totalAssetsBefore - lostAmount) * WAD / totalAssetsBefore;

        uint256 poolTokenSupply = pool.liquidStakingToken().totalSupply();
        uint256 tokenPrice = poolTokenSupply * WAD / (totalAssetsBefore - lostAmount);

        // by checking converting 1 poolToken to its asset equivalent should mirror the recoverPercent
        assertEq(pool.convertToAssets(WAD), recoverPercent, "IFILtoFIL should be 1");
        assertEq(pool.convertToShares(WAD), tokenPrice, "FILtoIFIL should be 1");
        assertEq(
            totalAssetsBefore + recoveredFunds - borrowAmount, totalAssetsAfter, "Pool should have recovered funds"
        );
        assertEq(lostAmount, borrowAmount - recoveredFunds, "lost amount should be correct");
        assertEq(pool.lpRewards().lost, 0, "lost rental fees should be 0 because no interest");

        assertEq(
            lostAmount,
            AccountHelpers.getAccount(router, agent.id(), pool.id()).principal,
            "Pool should have written down assets correctly"
        );
        assertEq(pool.totalBorrowed(), 0, "Pool should have nothing borrwed after the liquidation");
        assertEq(wFIL.balanceOf(address(police)), 0, "Agent police should not have funds");
        assertTrue(police.agentLiquidated(agent.id()), "Agent should be marked as liquidated");
        testInvariants("testDistributeLiquidatedFunds");
        if (lostAmount == 0) {
            assertPegInTact();
        }
    }

    function testDistributeLiquidatedFundsFullRecoveryNoInterest(uint256 borrowAmount, uint256 recoveredFunds) public {
        borrowAmount = bound(borrowAmount, WAD, stakeAmount);
        recoveredFunds = bound(recoveredFunds, borrowAmount, stakeAmount);

        setAgentDefaulted(agent, borrowAmount);

        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();

        vm.deal(policeOwner, recoveredFunds);
        vm.startPrank(policeOwner);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);

        assertPegInTact();

        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();

        assertPegInTact();

        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
        assertTrue(account.defaulted, "Agent should be defaulted");
        assertEq(totalAssetsBefore, totalAssetsAfter, "Pool should have recovered fully");
        assertEq(
            wFIL.balanceOf(address(pool)), totalAssetsAfter, "Pool should have received the correct amount of wFIL"
        );

        // compute the extra amount that should be paid back to the owner and the treasury
        // we use the borrowAmountBefore because no debt has accrued, really this should be totalBorrowed+interestOwed
        uint256 liquidationFee = totalBorrowedBefore.mulWadDown(police.liquidationFee());
        // the owner should get back excess and the treasury should get back its 10% liquidation fee
        if (recoveredFunds > totalBorrowedBefore + liquidationFee) {
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                recoveredFunds - totalBorrowedBefore - liquidationFee,
                "Police owner should only have paid the amount owed"
            );
            assertEq(
                wFIL.balanceOf(GetRoute.treasury(router)),
                liquidationFee,
                "Police should have received the treasury fee"
            );
        } else if (recoveredFunds > totalBorrowedBefore) {
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                0,
                "Owner should not get funds back if liquidation fee isnt fully paid"
            );
            assertEq(
                wFIL.balanceOf(GetRoute.treasury(router)),
                recoveredFunds - totalBorrowedBefore,
                "Police should have received some liquidation fee"
            );
        } else {
            // no liquidation fee should be paid if the recovered funds are less than the total borrowed
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                0,
                "Owner should not get funds back if liquidation fee isnt fully paid"
            );
            assertEq(wFIL.balanceOf(GetRoute.treasury(router)), 0, "No liquidation fees should have been paid");
        }
        assertTrue(police.agentLiquidated(agent.id()), "Agent should be marked as liquidated");
        testInvariants("testDistributeLiquidatedFundsFullRecovery");
    }

    function testDistributeLiquidationFundsPartialRecoveryWithInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD + 1, stakeAmount);
        recoveredFunds = bound(recoveredFunds, WAD, borrowAmount - 1);
        setAgentDefaulted(agent, borrowAmount);

        // roll forward a year to get some interest
        vm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwed = pool.getAgentInterestOwed(agent.id());
        uint256 interestOwedLessTFees = interestOwed.mulWadUp(1e18 - pool.treasuryFeeRate());

        vm.deal(policeOwner, recoveredFunds);
        vm.startPrank(policeOwner);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);

        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();
        uint256 filValOf1iFILBeforeLiquidation = pool.convertToAssets(WAD);

        assertEq(
            totalAssetsBefore, stakeAmount + interestOwedLessTFees, "Total assets before should exclude treasury fees"
        );

        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();
        uint256 totalAccrued = pool.lpRewards().accrued;
        uint256 interestAccruedLessTFees = totalAccrued.mulWadUp(1e18 - pool.treasuryFeeRate());

        uint256 lostAssets = totalBorrowedBefore + interestAccruedLessTFees - recoveredFunds;
        uint256 recoverPercent = (totalAssetsBefore - lostAssets).divWadDown(totalAssetsBefore);

        assertEq(
            totalAssetsAfter,
            stakeAmount + recoveredFunds + interestAccruedLessTFees - totalBorrowedBefore - interestOwedLessTFees,
            "Pool should have lost all interest and princpal"
        );

        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());

        assertEq(
            account.principal,
            interestOwed + borrowAmount - recoveredFunds,
            "no principal was paid, so account.principal should be the original principal amount lost"
        );
        assertEq(pool.treasuryFeesOwed(), 0, "Treasury fees should be 0 after a partial liquidation");
        assertApproxEqAbs(
            pool.convertToAssets(WAD),
            filValOf1iFILBeforeLiquidation.mulWadDown(recoverPercent),
            1e3,
            "IFIL should have devalued correctly"
        );
        assertEq(pool.totalBorrowed(), 0, "Pool should have nothing borrowed after liquidation");
        assertEq(totalAssetsBefore - totalAssetsAfter, lostAssets, "lost assets should be correct");
        if (recoveredFunds >= interestOwed) {
            assertEq(pool.lpRewards().lost, 0, "pool should not lose rental fees");
            assertEq(pool.lpRewards().paid, interestOwed, "pool should have paid rental fees");
        } else {
            assertEq(
                pool.lpRewards().paid,
                recoveredFunds,
                "paid rental fees should be the full recover amount when the recover amount is less than the interest owed"
            );
            assertEq(pool.lpRewards().lost, interestOwed - recoveredFunds, "lost assets should be correct");
        }
    }

    function testDistributeLiquidationFundsFullRecoveryWithInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD, stakeAmount);

        setAgentDefaulted(agent, borrowAmount);

        // roll forward a year to get some interest
        vm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwed = pool.getAgentInterestOwed(agent.id());
        uint256 interestOwedLessTFees = interestOwed.mulWadUp(1e18 - pool.treasuryFeeRate());
        // here its important to test the range where the recovered funds are enough to cover principal + interest owed to LPs ( but not enough to pay off the full interest owed, which includes t fees)
        recoveredFunds = bound(recoveredFunds, borrowAmount + interestOwedLessTFees, MAX_FIL);

        vm.deal(policeOwner, recoveredFunds);
        vm.startPrank(policeOwner);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);

        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 filValOf1iFILBeforeLiquidation = pool.convertToAssets(WAD);
        uint256 totalDebtLessTFees = interestOwedLessTFees + borrowAmount;

        assertEq(
            totalAssetsBefore, stakeAmount + interestOwedLessTFees, "Total assets before should exclude treasury fees"
        );

        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();

        assertEq(totalAssetsBefore, totalAssetsAfter, "Pool should have recovered fully");

        // compute the extra amount that should be paid back to the owner and the treasury
        // we use the borrowAmountBefore because no debt has accrued, really this should be totalBorrowed+interestOwed
        uint256 liquidationFee = totalDebtLessTFees.mulWadDown(police.liquidationFee());
        // the owner should get back excess and the treasury should get back its 10% liquidation fee
        if (recoveredFunds > totalDebtLessTFees + liquidationFee) {
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                recoveredFunds - totalDebtLessTFees - liquidationFee,
                "Police owner should only have paid the amount owed"
            );
            assertEq(
                wFIL.balanceOf(GetRoute.treasury(router)),
                liquidationFee,
                "Police should have received the treasury fee"
            );
        } else if (recoveredFunds > totalDebtLessTFees) {
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                0,
                "Owner should not get funds back if liquidation fee isnt fully paid"
            );
            assertEq(
                wFIL.balanceOf(GetRoute.treasury(router)),
                recoveredFunds - totalDebtLessTFees,
                "Police should have received some liquidation fee"
            );
        } else {
            // no liquidation fee should be paid if the recovered funds are less than the total borrowed
            assertEq(
                wFIL.balanceOf(IAuth(address(agent)).owner()),
                0,
                "Owner should not get funds back if liquidation fee isnt fully paid"
            );
            assertEq(wFIL.balanceOf(GetRoute.treasury(router)), 0, "No liquidation fees should have been paid");
        }

        assertEq(filValOf1iFILBeforeLiquidation, pool.convertToAssets(WAD), "IFILtoFIL should not change");
    }
}

contract AgentUpgradeTest is ProtocolTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 10e18;
    IAgent agent;
    uint64 miner;
    address prevAgentAddr;

    function setUp() public {
        _depositFundsIntoPool(stakeAmount, investor1);
        (agent, miner) = configureAgent(minerOwner);
        prevAgentAddr = address(agent);
    }

    function testUpgradeNoAuth() public {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agentFactory.upgradeAgent(prevAgentAddr);
    }

    function testUpgradeSameAgentVersion() public {
        address agentOwner = _agentOwner(agent);
        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        vm.prank(agentOwner);
        try agentFactory.upgradeAgent(prevAgentAddr) {
            assertTrue(false, "Should have reverted");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testDecommissionedAgentAction() public {
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);
        address agentOperator = _agentOperator(agent);
        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();
        vm.prank(minerOwner);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));
        assertEq(newAgent.id(), agentId);
        assertEq(_agentOwner(newAgent), agentOwner);
        assertEq(_agentOperator(newAgent), agentOperator);

        uint256 poolId = pool.id();

        SignedCredential memory borrowCred = issueGenericBorrowCred(agentId, 1e18);

        vm.startPrank(_agentOwner(agent));
        // make sure the old agent can't do anything
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.borrow(poolId, borrowCred);

        SignedCredential memory addMinerCred = issueAddMinerCred(agentId, 0);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.addMiner(addMinerCred);

        SignedCredential memory removeMinerCred = issueRemoveMinerCred(agentId, 0, emptyAgentData());
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.removeMiner(1234, removeMinerCred);

        SignedCredential memory payCred = issueGenericPayCred(agentId, WAD);
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.pay(poolId, payCred);

        SignedCredential memory withdrawCred = issueWithdrawCred(agentId, WAD, emptyAgentData());
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.withdraw(makeAddr("receiver"), withdrawCred);

        vm.stopPrank();
    }

    function testUpgradeBasic() public {
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);
        address agentOperator = _agentOperator(agent);
        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();
        vm.prank(minerOwner);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));
        assertEq(newAgent.id(), agentId);
        assertEq(_agentOwner(newAgent), agentOwner);
        assertEq(_agentOperator(newAgent), agentOperator);
    }

    function testUpgradeFromAdministration() public {
        address administration = makeAddr("ADMINISTRATION");
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);
        address agentOperator = _agentOperator(agent);

        // put the agent into default
        putAgentOnAdministration(agent, administration, EPOCHS_IN_YEAR, 1e18);

        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();

        vm.startPrank(administration);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));
        assertEq(newAgent.id(), agentId);
        assertEq(_agentOwner(newAgent), agentOwner);
        assertEq(_agentOperator(newAgent), agentOperator);
    }

    function testUpgradeFromAdministrationInvalid() public {
        address administration = makeAddr("ADMINISTRATION");

        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();

        vm.startPrank(administration);
        vm.expectRevert(Unauthorized.selector);
        IAgent(agentFactory.upgradeAgent(prevAgentAddr));
    }

    function testAccountPersistsThroughUpdate() public {
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);

        // put the agent into default
        agentBorrow(agent, issueGenericBorrowCred(agentId, 1e18));

        Account memory preUpgradeAcc = AccountHelpers.getAccount(router, agentId, pool.id());

        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();

        Account memory postUpgradeAcc = AccountHelpers.getAccount(router, agentId, pool.id());

        vm.startPrank(agentOwner);
        agentFactory.upgradeAgent(prevAgentAddr);

        assertEq(preUpgradeAcc.epochsPaid, postUpgradeAcc.epochsPaid);
        assertEq(preUpgradeAcc.principal, postUpgradeAcc.principal);
        assertEq(preUpgradeAcc.defaulted, postUpgradeAcc.defaulted);
        assertEq(preUpgradeAcc.startEpoch, postUpgradeAcc.startEpoch);
    }

    function testDecommissionAgentNoAuth() public {
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agent.decommissionAgent(address(agent));
    }

    function testUpgradeFundsForward(uint256 filBal, uint256 wFILBal) public {
        filBal = bound(filBal, 0, MAX_FIL / 2);
        wFILBal = bound(wFILBal, 0, MAX_FIL / 2);

        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);
        address agentOperator = _agentOperator(agent);

        _upgradeAgentDeployer();

        vm.deal(prevAgentAddr, filBal + wFILBal);
        // give the agent some WFIL to push
        vm.prank(prevAgentAddr);
        wFIL.deposit{value: wFILBal}();

        assertEq(wFIL.balanceOf(prevAgentAddr), wFILBal, "agent should have wFIL");
        assertEq(prevAgentAddr.balance, filBal, "agent should have FIL");

        vm.prank(minerOwner);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));
        assertEq(newAgent.id(), agentId);
        assertEq(_agentOwner(newAgent), agentOwner);
        assertEq(_agentOperator(newAgent), agentOperator);
        assertEq(address(newAgent).balance, filBal + wFILBal, "new agent should have funds");
        assertEq(wFIL.balanceOf(prevAgentAddr), 0, "old agent should have no funds in wFIL");
        assertEq(prevAgentAddr.balance, 0, "old agent should have no funds in FIL");
    }

    function testUpgradeMigrateMiner() public {
        uint64[] memory miners = new uint64[](1);
        miners[0] = miner;

        IMinerRegistry registry = GetRoute.minerRegistry(router);
        IAgentFactory agentFactory = GetRoute.agentFactory(router);

        _upgradeAgentDeployer();

        assertTrue(registry.minerRegistered(agent.id(), miner), "Agent should have miner before removing");
        assertEq(registry.minersCount(agent.id()), 1, "Agent should have 1 miner");

        vm.prank(minerOwner);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));

        vm.prank(address(newAgent));
        agent.migrateMiner(miner);

        vm.prank(minerOwner);
        UpgradedAgent(payable(address(newAgent))).addMigratedMiners(miners);
        assertTrue(registry.minerRegistered(newAgent.id(), miner), "miner should still be registed to the agent");
        assertTrue(miner.isOwner(address(newAgent)), "The mock miner's owner should change to the new agent");
    }

    function _upgradeAgentDeployer() internal {
        UpgradedAgentDeployer deployer = new UpgradedAgentDeployer();

        vm.prank(systemAdmin);
        IRouter(router).pushRoute(ROUTE_AGENT_DEPLOYER, address(deployer));
    }
}

contract AgentDataTest is ProtocolTest {
    using Credentials for VerifiableCredential;

    function testGreenScore(uint32 greenScore) public {
        AgentData memory data = AgentData(
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            0,
            // Green Score
            greenScore
        );
        VerifiableCredential memory vc = VerifiableCredential(address(0x0), 0, 0, 0, 0, bytes4(0), 0, abi.encode(data));
        assertEq(vc.getGreenScore(credParser), greenScore, "Green score should be correct");
    }

    function testFaultySectors(uint256 faultySectors) public {
        AgentData memory data = AgentData(0, 0, 0, 0, 0, 0, 0, faultySectors, 0, 0);
        VerifiableCredential memory vc = VerifiableCredential(address(0x0), 0, 0, 0, 0, bytes4(0), 0, abi.encode(data));
        assertEq(vc.getFaultySectors(credParser), faultySectors, "Faulty sectors should be correct");
    }

    function testLiveSectors(uint256 liveSectors) public {
        AgentData memory data = AgentData(0, 0, 0, 0, 0, 0, 0, 0, liveSectors, 0);
        VerifiableCredential memory vc = VerifiableCredential(address(0x0), 0, 0, 0, 0, bytes4(0), 0, abi.encode(data));
        assertEq(vc.getLiveSectors(credParser), liveSectors, "Live sectors should be correct");
    }
}
