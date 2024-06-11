// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase
pragma solidity 0.8.17;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {BytesLib} from "bytes-utils/BytesLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "test/helpers/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
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

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    Agent agent;

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

    function testTransferOwner() public {
        address owner = makeAddr("OWNER");
        vm.prank(minerOwner1);
        agent.transferOwnership(owner);
        assertEq(agent.pendingOwner(), owner);
        vm.prank(owner);
        agent.acceptOwnership();
        assertEq(agent.owner(), owner);
    }

    function testTransferOperator() public {
        address operator = makeAddr("OPERATOR");
        vm.prank(minerOwner1);
        agent.transferOperator(operator);
        assertEq(agent.pendingOperator(), operator);
        vm.prank(operator);
        agent.acceptOperator();
        assertEq(agent.operator(), operator);
    }

    function testSetAdoRequestKey(address pubKey) public {
        vm.startPrank(agent.owner());
        agent.setAdoRequestKey(pubKey);
        assertEq(agent.adoRequestKey(), pubKey);
    }

    function testReceive() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (Agent agent1,) = configureAgent(investor1);
        uint256 agentFILBal = address(agent1).balance;

        vm.prank(investor1);
        (bool sent,) = payable(address(agent1)).call{value: transferAmt}("");
        assertTrue(sent);
        assertEq(address(agent1).balance, agentFILBal + transferAmt);
    }

    function testFallback() public {
        uint256 transferAmt = 1e18;

        vm.deal(investor1, transferAmt);
        (Agent _agent,) = configureAgent(investor1);
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

contract AgentPushPullFundsTest is BaseTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    Agent agent;

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

contract AgentRmEquityTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = MAX_FIL;

    IAgent agent;
    uint64 miner;
    IPool pool;
    IAgentPolice agentPolice;

    function setUp() public {
        pool = createAndFundPool(depositAmt, investor1);
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
            bal,
            // EDR does not matter for this test
            0
        );

        withdrawAndAssert(receiver, withdrawAmount, withdrawCred);
    }

    /// @dev this test only checks against the AgentPolice DTE check, it does not check against the pool's checks
    function testWithdrawWithOutstandingPrincipal(
        uint256 withdrawAmount,
        uint256 principal,
        uint256 liquidationValue,
        uint256 agentValue,
        uint256 edr
    ) public {
        // make sure to have at least 1 FIL worth of principal
        principal = bound(principal, WAD, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        // agentValue includes principal, so it should never be less than principal
        agentValue = bound(agentValue, liquidationValue, MAX_FIL);
        // cannot withdraw more than the balance on agent
        withdrawAmount = bound(withdrawAmount, 0, agentValue);
        edr = bound(edr, 0, MAX_FIL);

        agentBorrow(agent, 0, issueGenericBorrowCred(agent.id(), principal));

        (address receiver, SignedCredential memory withdrawCred) =
            customWithdrawCred(withdrawAmount, principal, agentValue, liquidationValue, edr);

        withdrawAndAssert(receiver, withdrawAmount, withdrawCred);
    }

    function testWithdrawIntoUnapprovedDTE(uint256 principal, uint256 equity) public {
        equity = bound(equity, 1e18, MAX_FIL);
        // make sure principal is at least max DTE above equity to get blocked by DTE
        principal = bound(principal, equity.mulWadDown(agentPolice.maxDTE() + 1), MAX_FIL * 3);
        uint256 withdrawAmt = principal;
        // make sure there is enough funds in the pool to cover principal
        depositFundsIntoPool(pool, principal, investor1);
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), principal));

        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            // withdraw amount doesn't matter in this test
            withdrawAmt,
            principal,
            // agent total value is equity + principal,
            equity + principal,
            // ensure collateral value does not interfere with this test
            type(uint256).max,
            // EDR does not matter for this test
            type(uint256).max
        );

        withdrawAndAssertRevert(receiver, withdrawCred, AgentPolice.OverLimitDTE.selector);
    }

    function testWithdrawIntoUnapprovedDTL(uint256 principal, uint256 liquidationValue) public {
        liquidationValue = bound(liquidationValue, 2e18, MAX_FIL);
        principal = bound(principal, liquidationValue.mulWadUp(agentPolice.maxDTL() + 1), MAX_FIL * 2);
        uint256 withdrawAmt = principal;
        depositFundsIntoPool(pool, principal, investor1);
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), principal));
        // create a withdraw credential
        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            withdrawAmt,
            principal,
            // agent value should be big number so DTE does not interfere in this test
            principal * 10,
            liquidationValue,
            // EDR does not matter for this test
            WAD
        );

        withdrawAndAssertRevert(receiver, withdrawCred, AgentPolice.OverLimitDTL.selector);
    }

    function testWithdrawIntoUnapprovedDTI(uint256 principal, uint256 badEDR) public {
        // in this test, we want EDR to be > maxDTI, so we set the principal to be
        // make principal large enough such that we can have a bad EDR
        principal = bound(principal, 1e18, MAX_FIL);
        uint256 withdrawAmt = principal;

        depositFundsIntoPool(pool, principal, investor1);
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), principal));

        uint256 badEDRUpper =
            _getAdjustedRate().mulWadUp(principal).mulWadUp(EPOCHS_IN_DAY).divWadDown(agentPolice.maxDTI());

        badEDR = bound(badEDR, 0, badEDRUpper);

        // liquidationValue needs to result in DTL < 80%
        // agent value needs to result in DTE < 300%
        uint256 agentValue = principal * 10;
        uint256 liquidationValue = agentValue;

        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            // withdraw amount doesn't matter in this test
            withdrawAmt,
            principal,
            agentValue,
            liquidationValue,
            badEDR
        );

        withdrawAndAssertRevert(receiver, withdrawCred, AgentPolice.OverLimitDTI.selector);
    }

    function testWithdrawMoreThanLiquid(uint256 bal, uint256 withdrawAmount) public {
        bal = bound(bal, 0, MAX_FIL);
        withdrawAmount = bound(withdrawAmount, bal + 1, MAX_FIL * 2);

        (address receiver, SignedCredential memory withdrawCred) = customWithdrawCred(
            withdrawAmount,
            // principal can be 0 as to not half the withdraw,
            0,
            bal,
            bal,
            // great EDR
            WAD
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
            DUST,
            // EDR does not matter for this test
            0
        );

        removeMinerAndAssert(miner, newMinerOwner, removeMinerCred);
    }

    /// @dev this test only checks against the AgentPolice DTE check
    function testRemoveMinerWithOutstandingPrincipal(
        uint256 principal,
        uint256 liquidationValue,
        uint256 agentValue,
        uint256 edr
    ) public {
        principal = bound(principal, WAD, MAX_FIL);
        liquidationValue = bound(liquidationValue, 0, MAX_FIL);
        // agentValue includes principal, so it should never be less than principal
        agentValue = bound(agentValue, liquidationValue, MAX_FIL);
        edr = bound(edr, 0, MAX_FIL);

        agentBorrow(agent, 0, issueGenericBorrowCred(agent.id(), principal));

        (uint64 newMinerOwner, SignedCredential memory removeMinerCred) =
            customRemoveMinerCred(miner, principal, agentValue, liquidationValue, edr);

        removeMinerAndAssert(miner, newMinerOwner, removeMinerCred);
    }

    function customWithdrawCred(
        uint256 withdrawAmount,
        uint256 principal,
        uint256 agentValue,
        uint256 liquidationValue,
        uint256 edr
    ) internal returns (address receiver, SignedCredential memory sc) {
        receiver = makeAddr("RECEIVER");
        vm.deal(address(agent), agentValue);

        AgentData memory agentData = AgentData(
            agentValue,
            liquidationValue,
            // no expected daily faults
            0,
            edr,
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

    function customRemoveMinerCred(
        uint64 minerToRemove,
        uint256 principal,
        uint256 agentValue,
        uint256 collateralValue,
        uint256 edr
    ) internal returns (uint64 newMinerOwnerId, SignedCredential memory rmMinerCred) {
        address newMinerOwner = makeAddr("NEW_MINER_OWNER");

        newMinerOwnerId = idStore.addAddr(newMinerOwner);

        AgentData memory agentData = AgentData(
            agentValue,
            collateralValue,
            // no expected daily faults
            0,
            edr,
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
        vm.startPrank(minerOwner);
        uint256 preAgentLiquidFunds = agent.liquidAssets();

        testInvariants(pool, "withdrawAndAssertSuccess - pre");

        bool shouldBeAllowed;
        bytes memory errorBytes;
        // we expect the agent to follow the agent police's logic, we test the agent police logic elsewhere
        try agentPolice.confirmRmEquity(withdrawCred.vc) {
            shouldBeAllowed = true;
        } catch (bytes memory b) {
            shouldBeAllowed = false;
            errorBytes = b;
        }

        // if the agent does not have liquid funds, the withdrawal will get stopped on insufficient funds
        if (shouldBeAllowed && agent.liquidAssets() < withdrawCred.vc.value) {
            shouldBeAllowed = false;
            errorBytes = BytesLib.slice(abi.encode(Agent.InsufficientFunds.selector), 0, 4);
        }

        if (shouldBeAllowed) {
            agent.withdraw(receiver, withdrawCred);

            assertEq(agent.liquidAssets(), preAgentLiquidFunds - withdrawAmount);
            assertEq(receiver.balance, withdrawAmount);
        } else {
            vm.expectRevert(errorBytes);
            agent.withdraw(receiver, withdrawCred);
        }

        testInvariants(pool, "withdrawAndAssertSuccess - post");
        vm.stopPrank();
    }

    function withdrawAndAssertRevert(address receiver, SignedCredential memory withdrawCred, bytes4 errorSelectorValue)
        internal
    {
        console.log("HETERERERT");
        uint256 preAgentLiquidFunds = agent.liquidAssets();
        // withdraw
        vm.startPrank(minerOwner);
        console.log("HERE");
        vm.expectRevert(abi.encodeWithSelector(errorSelectorValue));
        agent.withdraw(receiver, withdrawCred);
        vm.stopPrank();

        console.log("HFNDOSFDS");

        assertEq(agent.liquidAssets(), preAgentLiquidFunds, "No funds should have been withdrawn");
        console.log("YOOOO");
        testInvariants(pool, "withdrawAndAssertRevert");
    }

    function removeMinerAndAssert(uint64 removedMiner, uint64 newMinerOwner, SignedCredential memory rmMinerCred)
        internal
    {
        vm.startPrank(minerOwner);
        uint256 preAgentMinersCount = GetRoute.minerRegistry(router).minersCount(agent.id());

        testInvariants(pool, "removeMinerAndAssert - pre");

        bool shouldBeAllowed;
        bytes memory errorBytes;
        // we expect the agent to follow the agent police's logic, we test the agent police logic elsewhere
        try agentPolice.confirmRmEquity(rmMinerCred.vc) {
            shouldBeAllowed = true;
        } catch (bytes memory b) {
            shouldBeAllowed = false;
            errorBytes = b;
        }

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

        testInvariants(pool, "removeMinerAndAssertSuccess");
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
        testInvariants(pool, "removeMinerAndAssertRevert");
    }
}

contract AgentBorrowingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
        pool = createAndFundPool(depositAmt, investor1);
        (agent, miner) = configureAgent(minerOwner);
    }

    function testBorrowValid(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, depositAmt);
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, pool.id(), borrowCred);
    }

    function testBorrowTwice(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, depositAmt / 2);

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        uint256 borrowBlock = block.number;
        agentBorrow(agent, pool.id(), borrowCred);
        console.log("----------- just borrowed 1 --------");
        // roll forward to test the startEpoch and epochsPaid
        vm.roll(block.number + 1000);

        borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
        // Since we've already borrowed, we pretend the SP locks substantially more funds
        uint256 collateralValue = borrowAmount * 4;

        AgentData memory agentData = createAgentData(
            collateralValue,
            borrowCred.vc.getExpectedDailyRewards(credParser),
            // principal = borrowAmount * 2 (second time borrowing)
            borrowAmount * 2
        );
        borrowCred.vc.claim = abi.encode(agentData);
        borrowCred = signCred(borrowCred.vc);
        console.log("------- before borrow 2 -------");
        agentBorrow(agent, pool.id(), borrowCred);
        console.log("------- after borrow 2 -------");

        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
        assertEq(account.principal, borrowAmount * 2);
        assertEq(account.startEpoch, borrowBlock);
        assertEq(account.epochsPaid, borrowBlock);
        testInvariants(pool, "testBorrowTwice");
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
        testInvariants(pool, "testBorrowMoreThanLiquid");
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
        testInvariants(pool, "testBorrowNothing");
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
        testInvariants(pool, "testBorrowNonOwnerOperator");
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
        testInvariants(pool, "testBorrowWrongCred");
    }
}

contract AgentPayTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    error AccountDNE();

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 depositAmt = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
        pool = createAndFundPool(depositAmt, investor1);
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
        (uint256 payAmount,) = calculateInterestOwed(borrowAmount, rollFwdAmt);
        // Set fuzzed values to logical test limits - in this case anyone but the agent should be unauthorized
        address payer = makeAddr(payerSeed);
        vm.assume(payer != address(agent));
        // Set up the test state

        // Borrow funds and roll forward to generate interest
        agentBorrow(agent, poolId, borrowCred);
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
        testInvariants(pool, "testNonAgentCannotPay");
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
        testInvariants(pool, "testCannotPayOnNonExistentAccount");
    }

    function testPayInterestOnly(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_WEEK * 3);
        borrowAmount = bound(borrowAmount, 1e18, depositAmt);

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
        (uint256 interestOwed, uint256 interestOwedPerEpoch) = calculateInterestOwed(borrowAmount, rollFwdAmt);

        // bind the pay amount to less than the interest owed
        payAmount = bound(payAmount, interestOwedPerEpoch + DUST, interestOwed - DUST);

        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, pool, borrowCred, payAmount, rollFwdAmt);

        assertEq(
            prePayState.agentBorrowed,
            AccountHelpers.getAccount(router, agent.id(), pool.id()).principal,
            "principal should not change"
        );
        testInvariants(pool, "testPayInterestOnly");
    }

    function testPayInterestAndPartialPrincipal(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_WEEK * 3);
        // bind borrow amount min 1e18 to ensure theres a decent amount of principal to repay
        borrowAmount = bound(borrowAmount, 1e18, depositAmt);

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        (uint256 interestOwed,) = calculateInterestOwed(borrowAmount, rollFwdAmt);
        // bind the pay amount to in between the interest owed and less than the principal
        payAmount = bound(payAmount, interestOwed + DUST, interestOwed + borrowAmount - DUST);

        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, pool, borrowCred, payAmount, rollFwdAmt);

        uint256 principalPaid = payAmount - interestOwed;

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

        assertEq(
            prePayState.agentBorrowed - principalPaid,
            postPaymentAccount.principal,
            "account should have decreased principal"
        );
        assertEq(postPaymentAccount.epochsPaid, block.number, "epochs paid should be current");
        testInvariants(pool, "testPayInterestAndPartialPrincipal");
    }

    function testPayFullExit(uint256 payAmount) public {}

    function testPayTooMuch(uint256 payAmount) public {}

    function borrowRollFwdAndPay(
        IAgent _agent,
        IPool newPool,
        SignedCredential memory borrowCred,
        uint256 payAmount,
        uint256 rollFwdAmt
    ) internal returns (StateSnapshot memory) {
        uint256 agentID = _agent.id();
        uint256 poolID = newPool.id();
        agentBorrow(_agent, poolID, borrowCred);

        vm.roll(block.number + rollFwdAmt);

        (,, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState) =
            agentPay(_agent, newPool, issueGenericPayCred(agentID, payAmount));

        assertPmtSuccess(_agent, newPool, prePayState, payAmount, principalPaid, refund);

        return prePayState;
    }

    function assertPmtSuccess(
        IAgent newAgent,
        IPool newPool,
        StateSnapshot memory prePayState,
        uint256 payAmount,
        uint256 principalPaid,
        uint256 refund
    ) internal {
        assertEq(
            prePayState.poolBalanceWFIL + payAmount, wFIL.balanceOf(address(newPool)), "pool should have received funds"
        );
        assertEq(
            prePayState.agentBalanceWFIL - payAmount, wFIL.balanceOf(address(newAgent)), "agent should have paid funds"
        );

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, newAgent.id(), newPool.id());

        // full exit
        if (principalPaid >= prePayState.agentBorrowed) {
            // refund should be greater than 0 if too much principal was paid
            if (principalPaid > prePayState.agentBorrowed) {
                assertEq(principalPaid - refund, prePayState.agentBorrowed, "should be a refund");
            }

            assertEq(postPaymentAccount.principal, 0, "principal should be 0");
            assertEq(postPaymentAccount.epochsPaid, 0, "epochs paid should be reset");
            assertEq(postPaymentAccount.startEpoch, 0, "start epoch should be reset");

            assertEq(
                _borrowedPoolsCount(agent.id()) - 1,
                prePayState.agentPoolBorrowCount,
                "agent should have removed pool from borrowed list"
            );
        } else {
            // partial exit or interest only payment
            assertGt(
                postPaymentAccount.epochsPaid, prePayState.accountEpochsPaid, "epochs paid should have moved forward"
            );
            assertLe(postPaymentAccount.epochsPaid, block.number, "epochs paid should not be in the future");
            assertEq(
                _borrowedPoolsCount(newAgent.id()),
                prePayState.agentPoolBorrowCount,
                "agent should not have removed pool from borrowed list"
            );
        }
        testInvariants(pool, "assertPaySuccess");
    }
}

contract AgentPoliceTest is BaseTest {
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
    IPool pool;
    IAgentPolice police;
    address policeOwner;

    function setUp() public {
        pool = createAndFundPool(stakeAmount, investor1);
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

    function testSetAdministrationWindow(uint256 newAdminWindow) public {
        vm.prank(systemAdmin);
        police.setAdministrationWindow(newAdminWindow);
        assertEq(police.administrationWindow(), newAdminWindow, "administration window should be set");
    }

    function testReplaySignature() public {
        SignedCredential memory sc = issueGenericBorrowCred(agent.id(), WAD);
        agentBorrow(agent, pool.id(), sc);

        FlipSig flipSig = new FlipSig();

        (uint8 flippedV, bytes32 flippedR, bytes32 flippedS) = flipSig.reuseSignature(sc.v, sc.r, sc.s);

        SignedCredential memory replayedCred = SignedCredential(sc.vc, flippedV, flippedR, flippedS);

        vm.startPrank(minerOwner);
        uint256 poolID = pool.id();
        vm.expectRevert("ECDSA: invalid signature 's' value");
        agent.borrow(poolID, replayedCred);

        vm.stopPrank();
    }

    function testPutAgentOnAdministration(uint256 rollFwdPeriod, uint256 borrowAmount) public {
        rollFwdPeriod = bound(rollFwdPeriod, police.administrationWindow() + 1, police.administrationWindow() * 10);

        borrowAmount = bound(borrowAmount, WAD, stakeAmount);
        // helper includes assertions
        putAgentOnAdministration(agent, administration, rollFwdPeriod, borrowAmount, pool.id());
        testInvariants(pool, "testPutAgentOnAdministration");
    }

    function testPutAgentOnAdministrationNoLoans() public {
        vm.startPrank(IAuth(address(police)).owner());
        try police.putAgentOnAdministration(address(agent), administration) {
            assertTrue(false, "Agent should not be eligible for administration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
        testInvariants(pool, "testPutAgentOnAdministrationNoLoans");
    }

    function testInvalidPutAgentOnAdministration() public {
        uint256 borrowAmount = WAD;

        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, pool.id(), borrowCred);

        vm.startPrank(IAuth(address(police)).owner());
        try police.putAgentOnAdministration(address(agent), administration) {
            assertTrue(false, "Agent should not be eligible for administration");
        } catch (bytes memory e) {
            assertEq(errorSelector(e), Unauthorized.selector);
        }
    }

    function testRmAgentFromAdministration() public {
        uint256 rollFwdPeriod = police.administrationWindow() + 100;
        uint256 borrowAmount = WAD;

        putAgentOnAdministration(agent, administration, rollFwdPeriod, borrowAmount, pool.id());

        // deal enough funds to the Agent so it can make a payment back to the Pool
        vm.deal(address(agent), borrowAmount * 4);

        SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

        // here we are exiting the pool by overpaying so much
        (, uint256 epochsPaid,,,) = agentPay(agent, pool, sc);

        require(epochsPaid == 0, "Should have exited from the pool");

        sc = issueGenericRecoverCred(agent.id(), 0, 1e18);
        // check that the agent is no longer on administration
        vm.startPrank(IAuth(address(agent)).owner());
        agent.setRecovered(sc);
        vm.stopPrank();

        assertEq(agent.administration(), address(0), "Agent Should not be on administration after paying up");
        testInvariants(pool, "testRmAgentFromAdministration");
    }

    function testSetAgentDefaulted() public {
        // helper includes assertions
        setAgentDefaulted(agent);
    }

    function testSetAdministrationNonAgentPolice(uint256 rollFwdPeriod) public {
        rollFwdPeriod = bound(rollFwdPeriod, police.administrationWindow() + 1, police.administrationWindow() * 10);

        uint256 borrowAmount = WAD;
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
        agentBorrow(agent, pool.id(), borrowCred);

        vm.roll(block.number + rollFwdPeriod);

        try police.putAgentOnAdministration(address(agent), administration) {
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
        try police.setAgentDefaultDTL(address(agent), issueGenericSetDefaultCred(agent.id())) {
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
        setAgentDefaulted(agent);

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
        testInvariants(pool, "testPrepareMinerForLiquidation");
    }

    function testDistributeLiquidatedFundsNonAgentPolice() public {
        setAgentDefaulted(agent);

        address prankster = makeAddr("prankster");
        vm.startPrank(prankster);
        vm.expectRevert(Unauthorized.selector);
        police.distributeLiquidatedFunds(address(agent), 0);
        testInvariants(pool, "testDistributeLiquidatedFundsNonAgentPolice");
    }

    function testDistributeLiquidatedFunds(uint256 borrowAmount, uint256 recoveredFunds) public {
        vm.startPrank(policeOwner);
        // set the agent in default
        police.setAgentDefaultDTL(address(agent), issueGenericSetDefaultCred(agent.id()));

        uint256 borrowedBefore = pool.totalBorrowed();
        uint256 totalAssetsBefore = pool.totalAssets();

        vm.deal(policeOwner, recoveredFunds);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);

        assertPegInTact(pool);
        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 borrowedAfter = pool.totalBorrowed();
        uint256 totalAssetsAfter = pool.totalAssets();

        uint256 lostAmount = totalAssetsBefore - pool.totalAssets();
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

        assertEq(
            borrowedBefore - borrowedAfter,
            AccountHelpers.getAccount(router, agent.id(), pool.id()).principal,
            "Pool should have written down assets correctly"
        );
        assertEq(wFIL.balanceOf(address(police)), 0, "Agent police should not have funds");
        assertTrue(police.agentLiquidated(agent.id()), "Agent should be marked as liquidated");
        testInvariants(pool, "testDistributeLiquidatedFunds");
        if (lostAmount == 0) {
            assertPegInTact(pool);
        }
    }

    function testDistributeLiquidatedFundsFullRecovery(
        uint256 rollFwdPeriod,
        uint256 borrowAmount,
        uint256 recoveredFunds
    ) public {
        borrowAmount = bound(borrowAmount, WAD, stakeAmount);
        rollFwdPeriod = bound(rollFwdPeriod, EPOCHS_IN_WEEK * 3 + 1, EPOCHS_IN_WEEK * 3 * 10);
        vm.assume(recoveredFunds > WAD);

        uint256 balanceAfter;
        uint256 balanceBefore;
        (uint256 interestOwed,) = calculateInterestOwed(borrowAmount, rollFwdPeriod);
        recoveredFunds = bound(recoveredFunds, borrowAmount, stakeAmount);
        balanceBefore = wFIL.balanceOf(address(pool));
        uint256 totalAssetsBefore = pool.totalAssets();
        setAgentDefaulted(agent);

        vm.deal(policeOwner, recoveredFunds);
        vm.startPrank(policeOwner);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(police), recoveredFunds);
        // distribute the recovered funds
        police.distributeLiquidatedFunds(address(agent), recoveredFunds);
        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
        assertTrue(account.defaulted, "Agent should be defaulted");
        balanceAfter = wFIL.balanceOf(address(pool));
        uint256 balanceChange =
            borrowAmount + interestOwed > recoveredFunds ? recoveredFunds : borrowAmount + interestOwed;
        assertEq(balanceAfter - balanceBefore, balanceChange, "Pool should have received the correct amount of funds");
        assertEq(
            wFIL.balanceOf(IAuth(address(agent)).owner()),
            recoveredFunds - balanceChange,
            "Police owner should only have paid the amount owed"
        );
        assertTrue(police.agentLiquidated(agent.id()), "Agent should be marked as liquidated");
        testInvariants(pool, "testDistributeLiquidatedFundsFullRecovery");

        uint256 gainAmount = pool.totalAssets() - totalAssetsBefore;
        uint256 gainPercent = (totalAssetsBefore + gainAmount) * WAD / totalAssetsBefore;

        uint256 poolTokenSupply = pool.liquidStakingToken().totalSupply();
        uint256 tokenPrice = poolTokenSupply * WAD / (totalAssetsBefore + gainAmount);
        // by checking converting 1 poolToken to its asset equivalent should mirror the recoverPercent
        assertEq(
            pool.convertToAssets(WAD),
            gainPercent,
            "IFILtoFIL should increase by the fees pay on top of the recovery amount"
        );
        assertEq(pool.convertToShares(WAD), tokenPrice, "FILtoIFIL should be 1");
    }
}

contract AgentUpgradeTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 10e18;
    IAgent agent;
    uint64 miner;
    IPool pool;
    address prevAgentAddr;

    function setUp() public {
        pool = createAndFundPool(stakeAmount, investor1);
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
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agentId, 1e18));
        vm.roll(block.number + EPOCHS_IN_YEAR);

        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        _upgradeAgentDeployer();

        vm.startPrank(systemAdmin);
        GetRoute.agentPolice(router).putAgentOnAdministration(address(agent), administration);
        vm.stopPrank();
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
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agentId, 1e18));

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

contract AgentDataTest is BaseTest {
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
