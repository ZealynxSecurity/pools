// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "test/helpers/MockMiner.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
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
import {Window} from "src/Types/Structs/Window.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {AgentBeneficiary, BeneficiaryHelpers} from "src/Types/Structs/Beneficiary.sol";
import {UpgradedAgentDeployer} from "test/helpers/UpgradedAgentDeployer.sol";
import {UpgradedAgent} from "test/helpers/UpgradedAgent.sol";
import {ROUTE_AGENT_FACTORY_ADMIN, ROUTE_MINER_REGISTRY} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
import {Roles} from "src/Constants/Roles.sol";
import {errorSelector} from "test/helpers/Utils.sol";
import "src/Constants/FuncSigs.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    error InvalidCredential();
    error InvalidParams();
    error InsufficientCollateral();
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

    function assertAgentPermissions(address operator, address owner, address agent) public {
      assertEq(Agent(payable(agent)).owner(), owner, "wrong owner");
      assertEq(Agent(payable(agent)).operator(), operator, "wrong operator");
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

    function testRouterConfigured() public {
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
      vm.stopPrank();

      assertEq(address(agent).balance, 0);
      assertEq(miner1.balance, pushAmount);
    }

    function testPushFundsToRandomMiner() public {
      uint64 secondMiner = _newMiner(minerOwner1);
      address miner2 = idStore.ids(secondMiner);

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
    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

    // no matter what statistics come in the credential, if no loans, can withdraw
    function testWithdrawWithNoLoans(
      uint256 bal,
      uint256 withdrawAmount
    ) public {
      vm.assume(bal >= withdrawAmount);

      vm.deal(address(agent), withdrawAmount);

      (
        address receiver,
        SignedCredential memory withdrawCred
      ) = customWithdrawCred(
        // balance doesn't matter in this test
        bal,
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

      withdrawAndAssertSuccess(
        receiver,
        withdrawAmount,
        withdrawCred
      );
    }

    /// @dev this test only checks against the AgentPolice DTE check, it does not check against the pool's checks
    function testWithdrawWithOutstandingPrincipal(
      uint256 bal,
      uint256 withdrawAmount,
      uint256 principal,
      uint256 agentValue
    ) public {
      bal = bound(bal, DUST, MAX_FIL);
      withdrawAmount = bound(withdrawAmount, 0, bal - DUST);
      principal = bound(principal, WAD, MAX_FIL);
      // agentValue includes principal, so it should never be less than principal
      agentValue = bound(agentValue, principal, MAX_FIL);

      (
        address receiver,
        SignedCredential memory withdrawCred
      ) = customWithdrawCred(
        bal,
        withdrawAmount,
        principal,
        agentValue,
        agentValue / 10,
        // EDR does not matter for this test
        WAD
      );

      uint256 preAgentBalance = address(agent).balance;

      uint256 equity = agentValue - principal;

      uint256 maxPoliceDTE = GetRoute.agentPolice(router).maxDTE();

      if (principal > (equity * maxPoliceDTE / WAD)) {
        // DTE > 1 -> no go
        withdrawAndAssertRevert(
          receiver,
          withdrawCred,
          AgentPolice.AgentStateRejected.selector
        );
      } else {
        // DTE <= 1
        withdrawAndAssertSuccess(
          receiver,
          withdrawAmount,
          withdrawCred
        );
      }
    }

    function testWithdrawIntoUnapprovedLTV(uint256 principal, uint256 collateralValue) public {
      collateralValue = bound(collateralValue, WAD, MAX_FIL);
      principal = bound(principal, collateralValue + DUST, MAX_FIL);

      // create an account to act as if a pool was created and the agent borrowed
      Account memory account = createAccount(principal);

      // set the account on the router and on the agent police
      vm.startPrank(address(pool));
      IRouter(router).setAccount(agent.id(), pool.id(), account);
      GetRoute.agentPolice(router).addPoolToList(agent.id(), pool.id());
      vm.stopPrank();

      // create a withdraw credential
      (
        address receiver,
        SignedCredential memory withdrawCred
      ) = customWithdrawCred(
        // balance doesn't matter in this test
        100e18,
        // withdraw amount doesn't matter in this test
        1e18,
        principal,
        collateralValue * 2,
        collateralValue,
        // EDR does not matter for this test
        WAD
      );

      withdrawAndAssertRevert(
        receiver,
        withdrawCred,
        AgentPolice.AgentStateRejected.selector
      );
    }

    function testWithdrawIntoUnapprovedDTI(uint256 principal, uint256 badEDR) public {
      // in this test, we want EDR to be > maxDTI, so we set the principal to be
      principal = bound(principal, WAD, MAX_FIL);
      uint256 rate = _getAdjustedRate(GCRED);

      IRateModule rateModule = IRateModule(pool.rateModule());

      uint256 badEDRUpper =
        _getAdjustedRate(GCRED)
        .mulWadUp(principal)
        .mulWadUp(EPOCHS_IN_DAY)
        .divWadDown(rateModule.maxDTE());

      badEDR = bound(badEDR, DUST, badEDRUpper - DUST);
      // collateral needs to result in LTV < 1
      uint256 collateralValue = principal * 3;
      // agent value needs to result in DTE < 1
      uint256 agentValue = collateralValue * 3;

      (
        address receiver,
        SignedCredential memory withdrawCred
      ) = customWithdrawCred(
        // balance doesn't matter in this test
        100e18,
        // withdraw amount doesn't matter in this test
        1e18,
        principal,
        // agent value needs to result in LTV < 1
        agentValue,
        // collateral value
        collateralValue,
        // EDR does not matter for this test
        badEDR
      );

      // create an account to act as if a pool was created and the agent borrowed
      Account memory account = createAccount(principal);

      // set the account on the router and on the agent police
      vm.startPrank(address(pool));
      IRouter(router).setAccount(agent.id(), pool.id(), account);
      GetRoute.agentPolice(router).addPoolToList(agent.id(), pool.id());
      vm.stopPrank();

      withdrawAndAssertRevert(
        receiver,
        withdrawCred,
        AgentPolice.AgentStateRejected.selector
      );
    }

    function testWithdrawMoreThanLiquid(
      uint256 bal,
      uint256 withdrawAmount,
      uint256 principal,
      uint256 agentValue
    ) public {
      bal = bound(bal, 0, MAX_FIL);
      withdrawAmount = bound(withdrawAmount, bal + 1, MAX_FIL);

      principal = bound(principal, WAD, MAX_FIL / 3);
      // ensure DTE < 1
      agentValue = bound(agentValue, principal * 3, MAX_FIL);

      (
        address receiver,
        SignedCredential memory withdrawCred
       ) = customWithdrawCred(
        bal,
        withdrawAmount,
        principal,
        agentValue,
        agentValue / 10,
        // great EDR
        WAD
      );

      withdrawAndAssertRevert(
        receiver,
        withdrawCred,
        Agent.InsufficientFunds.selector
      );
    }

    function customWithdrawCred(
      uint256 bal,
      uint256 withdrawAmount,
      uint256 principal,
      uint256 agentValue,
      uint256 collateralValue,
      uint256 edr
    ) internal returns (
      address receiver,
      SignedCredential memory sc
    ) {
      receiver = makeAddr("RECEIVER");
      vm.deal(address(agent), bal);

      AgentData memory agentData = AgentData(
        agentValue,
        DEFAULT_BASE_RATE,
        collateralValue,
        // no expected daily faults
        0,
        edr,
        GCRED,
        // locked funds are 50% of the agent's value
        agentValue / 50,
        10e18,
        principal,
        0
      );

      sc = issueWithdrawCred(
        agent.id(),
        withdrawAmount,
        agentData
      );
    }

    // no matter what statistics come in the credential, if no loans, can remove miner
    function testRemoveMinerWithNoLoans() public {
      (
        address newMinerOwner,
        SignedCredential memory removeMinerCred
      ) = customRemoveMinerCred(
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

      removeMinerAndAssertSuccess(
        miner,
        newMinerOwner,
        removeMinerCred
      );
    }

    /// @dev this test only checks against the AgentPolice DTE check, it does not check against the pool's checks
    function testRemoveMinerWithOutstandingPrincipal(
      uint256 principal,
      uint256 agentValue
    ) public {
      principal = bound(principal, WAD, MAX_FIL);
      // agentValue includes principal, so it should never be less than principal
      agentValue = bound(agentValue, principal, MAX_FIL);

      (
        address newMinerOwner,
        SignedCredential memory removeMinerCred
      ) = customRemoveMinerCred(
        // balance doesn't matter in this test
        miner,
        principal,
        agentValue,
        // collateral value
        agentValue / 10,
        // EDR does not matter for this test
        WAD
      );

      uint256 equity = agentValue - principal;

      if (principal > equity) {
        // DTE > 1 -> no go
        removeMinerAndAssertRevert(
          miner,
          newMinerOwner,
          removeMinerCred,
          AgentPolice.AgentStateRejected.selector
        );
      } else {
        // DTE <= 1
        removeMinerAndAssertSuccess(
          miner,
          newMinerOwner,
          removeMinerCred
        );
      }
    }

    function testRemoveMinerWithActiveBeneficiary(
      uint256 principal,
      uint256 agentValue,
      uint256 expiration,
      uint256 quota,
      uint256 withdrawAmount
    ) public {
      address beneficiary = makeAddr("BENNY");

      principal = bound(principal, WAD, MAX_FIL);
      // agentValue includes principal, so it should never be less than principal
      agentValue = bound(agentValue, principal, MAX_FIL);
      // make sure the beneficiary is active
      expiration = bound(expiration, block.number + 100000, type(uint256).max);
      quota = bound(quota, WAD, MAX_FIL);
      // ensure we have some unused quota left
      withdrawAmount = bound(withdrawAmount, 0, DUST);
      // set up benny
      configureBeneficiary(agent, beneficiary, expiration, quota);

      vm.assume(beneficiary != address(0));
      vm.deal(address(agent), withdrawAmount);
      // take some money out of the agent to increase quota
      vm.startPrank(beneficiary);
      agent.withdraw(
        beneficiary,
        issueWithdrawCred(agent.id(), withdrawAmount, emptyAgentData())
      );
      vm.stopPrank();

      (
        address newMinerOwner,
        SignedCredential memory removeMinerCred
      ) = customRemoveMinerCred(
        // balance doesn't matter in this test
        miner,
        principal,
        agentValue,
        // collateral value
        agentValue / 10,
        // EDR does not matter for this test
        WAD
      );

      AgentBeneficiary memory benny = GetRoute.agentPolice(router).agentBeneficiary(agent.id());

      uint256 unused = benny.active.quota - benny.active.usedQuota;
      uint256 equity = agentValue > principal
        ? agentValue - principal
        : 0;
      // DTE (including additional beneficiary liability) > 1
      if (principal + unused > (equity * GetRoute.agentPolice(router).maxDTE()) / WAD) {
        // DTE > 1 -> no go
        removeMinerAndAssertRevert(
          miner,
          newMinerOwner,
          removeMinerCred,
          AgentPolice.AgentStateRejected.selector
        );
      } else {
        // DTE <= 1
        removeMinerAndAssertSuccess(
          miner,
          newMinerOwner,
          removeMinerCred
        );
      }
    }

    function customRemoveMinerCred(
      uint64 miner,
      uint256 principal,
      uint256 agentValue,
      uint256 collateralValue,
      uint256 edr
    ) internal returns (
      address newMinerOwner,
      SignedCredential memory rmMinerCred
    ) {
      newMinerOwner = makeAddr("NEW_MINER_OWNER");

      AgentData memory agentData = AgentData(
        agentValue,
        DEFAULT_BASE_RATE,
        collateralValue,
        // no expected daily faults
        0,
        edr,
        GCRED,
        // locked funds are 50% of the agent's value
        agentValue / 50,
        10e18,
        principal,
        0
      );

      rmMinerCred = issueRemoveMinerCred(
        agent.id(),
        miner,
        agentData
      );
    }

    function withdrawAndAssertSuccess(
      address receiver,
      uint256 withdrawAmount,
      SignedCredential memory withdrawCred
    ) internal {
      uint256 preAgentLiquidFunds = agent.liquidAssets();

      vm.startPrank(minerOwner);
      agent.withdraw(receiver, withdrawCred);
      vm.stopPrank();

      assertEq(agent.liquidAssets(), preAgentLiquidFunds - withdrawAmount);
      assertEq(receiver.balance, withdrawAmount);
    }

    function withdrawAndAssertRevert(
      address receiver,
      SignedCredential memory withdrawCred,
      bytes4 errorSelector
    ) internal {
      uint256 preAgentLiquidFunds = agent.liquidAssets();
      // withdraw
      vm.startPrank(minerOwner);
      vm.expectRevert(abi.encodeWithSelector(errorSelector));
      agent.withdraw(receiver, withdrawCred);
      vm.stopPrank();

      assertEq(
        agent.liquidAssets(),
        preAgentLiquidFunds,
        "No funds should have been withdrawn"
      );
    }

    function removeMinerAndAssertSuccess(
      uint64 removedMiner,
      address newMinerOwner,
      SignedCredential memory rmMinerCred
    ) internal {
      vm.startPrank(minerOwner);
      agent.removeMiner(newMinerOwner, rmMinerCred);
      vm.stopPrank();

      assertEq(GetRoute.minerRegistry(router).minersCount(agent.id()), 0, "Agent should have no miners registered");
      assertFalse(GetRoute.minerRegistry(router).minerRegistered(agent.id(), miner), "Miner should not be registered after removing");
      assertEq(IMockMiner(idStore.ids(removedMiner)).proposed(), newMinerOwner, "Miner should have new propsed owner");
    }

    function removeMinerAndAssertRevert(
      uint64 removedMiner,
      address newMinerOwner,
      SignedCredential memory rmMinerCred,
      bytes4 errorSelector
    ) internal {
      vm.startPrank(minerOwner);
      vm.expectRevert(abi.encodeWithSelector(errorSelector));
      agent.removeMiner(newMinerOwner, rmMinerCred);
      vm.stopPrank();

      assertEq(GetRoute.minerRegistry(router).minersCount(agent.id()), 1, "Agent should have 1 miner registered");
      assertTrue(GetRoute.minerRegistry(router).minerRegistered(agent.id(), miner), "Miner should be registered");
      assertEq(IMockMiner(idStore.ids(removedMiner)).proposed(), address(0), "Miner should not have new propsed owner");
    }
}

contract AgentBorrowingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

    function testBorrowValid(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, WAD, stakeAmount);
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      agentBorrow(agent, pool.id(), borrowCred);
    }

    function testBorrowTwice(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, WAD, stakeAmount / 2);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      uint256 borrowBlock = block.number;
      agentBorrow(agent, pool.id(), borrowCred);
      // roll forward to test the startEpoch and epochsPaid
      vm.roll(block.number + 1000);

      borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      // Since we've already borrowed, we pretend the SP locks substantially more funds
      uint256 collateralValue = borrowAmount * 4;

      uint256 adjustedRate = rateArray[GCRED - pool.rateModule().minGCRED()] * DEFAULT_BASE_RATE / 1e18;

      AgentData memory agentData = createAgentData(
        collateralValue,
        GCRED,
        borrowCred.vc.getExpectedDailyRewards(credParser),
        // principal = borrowAmount * 2 (second time borrowing)
        borrowAmount * 2,
        // Account started at previous borrow block
        borrowBlock
      );
      borrowCred.vc.claim = abi.encode(agentData);
      borrowCred = signCred(borrowCred.vc);
      agentBorrow(agent, pool.id(), borrowCred);

      Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
      assertEq(account.principal, borrowAmount * 2);
      assertEq(account.startEpoch, borrowBlock);
      assertEq(account.epochsPaid, borrowBlock);
    }

    function testBorrowMoreThanLiquid(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, stakeAmount + 1, MAX_FIL);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      vm.startPrank(minerOwner);
      try agent.borrow(pool.id(), borrowCred) {
        assertTrue(false, "should not be able to borrow more than liquid");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), InsufficientLiquidity.selector);
      }

      vm.stopPrank();
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
    }
}

contract AgentPayTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;
    error AccountDNE();

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

    function testNonAgentCannotPay(string memory payerSeed) public {
      // Establish Static Params
      uint256 borrowAmount = 10e18;
      uint256 poolId = pool.id();
      uint256 agentId = agent.id();
      uint256 rollFwdAmt = GetRoute.agentPolice(router).defaultWindow() / 2;
      SignedCredential memory borrowCred = issueGenericBorrowCred(agentId, borrowAmount);

      // We're just going to use the full amount of interest owed as our pay amount
      (uint256 payAmount,) = calculateInterestOwed(agent, pool, borrowCred.vc, borrowAmount, rollFwdAmt);
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

    }

    function testPayInterestOnly(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
      rollFwdAmt = bound(rollFwdAmt, 1, GetRoute.agentPolice(router).defaultWindow() - 1);
      borrowAmount = bound(borrowAmount, 1e18, stakeAmount);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      (uint256 interestOwed, uint256 interestOwedPerEpoch) = calculateInterestOwed(agent, pool, borrowCred.vc, borrowAmount, rollFwdAmt);

      // bind the pay amount to less than the interest owed
      payAmount = bound(payAmount, interestOwedPerEpoch + DUST, interestOwed - DUST);

      StateSnapshot memory prePayState = borrowRollFwdAndPay(
        agent,
        pool,
        borrowCred,
        borrowAmount,
        payAmount,
        rollFwdAmt
      );

      assertEq(
        prePayState.agentBorrowed,
        AccountHelpers.getAccount(router, agent.id(), pool.id()).principal,
        "principal should not change"
      );
    }

    function testPayInterestAndPartialPrincipal(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
      rollFwdAmt = bound(rollFwdAmt, 1, GetRoute.agentPolice(router).defaultWindow() - 1);
      // bind borrow amount min 1e18 to ensure theres a decent amount of principal to repay
      borrowAmount = bound(borrowAmount, 1e18, stakeAmount);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      (uint256 interestOwed,) = calculateInterestOwed(agent, pool, borrowCred.vc, borrowAmount, rollFwdAmt);
      // bind the pay amount to in between the interest owed and less than the principal
      payAmount = bound(payAmount, interestOwed + DUST, interestOwed + borrowAmount - DUST);

      StateSnapshot memory prePayState = borrowRollFwdAndPay(
        agent,
        pool,
        borrowCred,
        borrowAmount,
        payAmount,
        rollFwdAmt
      );

      uint256 principalPaid = payAmount - interestOwed;

      Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

      assertEq(
        prePayState.agentBorrowed - principalPaid,
        postPaymentAccount.principal,
        "account should have decreased principal"
      );
      assertEq(postPaymentAccount.epochsPaid, block.number, "epochs paid should be current");
    }

    function testPayFullExit(uint256 payAmount) public {}

    function testPayTooMuch(uint256 payAmount) public {}

    function borrowRollFwdAndPay(
      IAgent agent,
      IPool pool,
      SignedCredential memory borrowCred,
      uint256 borrowAmount,
      uint256 payAmount,
      uint256 rollFwdAmt
    ) internal returns (
      StateSnapshot memory
    ) {
      uint256 agentID = agent.id();
      uint256 poolID = pool.id();
      agentBorrow(agent, poolID, borrowCred);

      vm.roll(block.number + rollFwdAmt);
      uint256 prevAccountEpochsPaid = AccountHelpers.getAccount(router, agentID, poolID).epochsPaid;
      uint256 prevAgentPoolBorrowCount = agent.borrowedPoolsCount();

      (
        ,uint256 epochsPaid,
        uint256 principalPaid,
        uint256 refund,
        StateSnapshot memory prePayState
      ) = agentPay(agent, pool, issueGenericPayCred(agentID, payAmount));

      assertPmtSuccess(agent, pool, prePayState, payAmount, principalPaid, refund);

      return prePayState;
    }

    function assertPmtSuccess(
      IAgent agent,
      IPool pool,
      StateSnapshot memory prePayState,
      uint256 payAmount,
      uint256 principalPaid,
      uint256 refund
    ) internal {
      assertEq(prePayState.poolBalanceWFIL + payAmount, wFIL.balanceOf(address(pool)), "pool should have received funds");
      assertEq(prePayState.agentBalanceWFIL - payAmount, wFIL.balanceOf(address(agent)), "agent should have paid funds");

      Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

      // full exit
      if (principalPaid >= prePayState.agentBorrowed) {
        // refund should be greater than 0 if too much principal was paid
        if (principalPaid > prePayState.agentBorrowed) {
          assertEq(principalPaid - refund, prePayState.agentBorrowed, "should be a refund");
        }

        assertEq(postPaymentAccount.principal, 0, "principal should be 0");
        assertEq(postPaymentAccount.epochsPaid, 0, "epochs paid should be reset");
        assertEq(postPaymentAccount.startEpoch, 0, "start epoch should be reset");

        assertEq(agent.borrowedPoolsCount() - 1, prePayState.agentPoolBorrowCount, "agent should have removed pool from borrowed list");
      } else {
        // partial exit or interest only payment
        assertGt(postPaymentAccount.epochsPaid, prePayState.accountEpochsPaid, "epochs paid should have moved forward");
        assertLe(postPaymentAccount.epochsPaid, block.number, "epochs paid should not be in the future");
        assertEq(agent.borrowedPoolsCount(), prePayState.agentPoolBorrowCount, "agent should not have removed pool from borrowed list");

      }
    }
}


contract AgentPoolsTest is BaseTest {
  using Credentials for VerifiableCredential;
  using AccountHelpers for Account;

  address investor1 = makeAddr("INVESTOR_1");
  address minerOwner = makeAddr("MINER_OWNER");
  uint256 stakeAmount = 1000e18;

  IAgent agent;
  uint64 miner;
  IPool pool;

  function setUp() public {
    // We only need a single agent instance across all pools
    IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
    agent = IAgent(agentFactory.create(minerOwner, minerOwner));
  }

  function testCreateRemoveMultiplePools(uint256 poolCount, uint256 totalBorrow) public {
    // NOTE: This has been tested up to 1000 but it takes a very long time to run
    poolCount = bound(poolCount, 1, 10);
    totalBorrow = bound(totalBorrow, WAD * poolCount, stakeAmount);
    uint256 borrowPerPool = totalBorrow / poolCount;
    uint256 borrowRemainder = totalBorrow % poolCount;
    IPool[] memory pools = new IPool[](poolCount);

    for (uint256 i = 0; i < poolCount; i++) {
      pools[i] = createFundBorrowPool(borrowPerPool);
    }

    assertEq(agent.borrowedPoolsCount(), poolCount, "agent should have correct pool count");

    for (uint256 i = 0; i < poolCount; i++) {
      SignedCredential memory sc = issueGenericPayCred(agent.id(), borrowPerPool*2);
      vm.deal(address(agent), borrowPerPool*2);

      (,uint256 epochsPaid,,,) = agentPay(agent, pools[i], sc);
    }
    assertEq(agent.borrowedPoolsCount(), 0, "agent should have correct pool count");

  }


  function createFundBorrowPool(uint256 amount) internal returns (IPool pool) {
    pool = createAndFundPool(stakeAmount, investor1);
    uint64 miner = _newMiner(minerOwner);
    _agentClaimOwnership(address(agent), miner, minerOwner);
    agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), amount));
    return pool;
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

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
      police = GetRoute.agentPolice(router);
    }

    function testPutAgentOnAdministration(uint256 rollFwdPeriod, uint256 borrowAmount) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      borrowAmount = bound(borrowAmount, WAD, stakeAmount);
      // helper includes assertions
      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );
    }

    function testPutAgentOnAdministrationNoLoans() public {
      vm.startPrank(IAuth(address(police)).owner());
      try police.putAgentOnAdministration(address(agent), administration) {
        assertTrue(false, "Agent should not be eligible for administration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), Unauthorized.selector);
      }
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
      uint256 rollFwdPeriod = police.defaultWindow() + 100;
      uint256 borrowAmount = WAD;

      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );

      // deal enough funds to the Agent so it can make a payment back to the Pool
      vm.deal(address(agent), borrowAmount * 4);

      SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

      // here we are exiting the pool by overpaying so much
      (,uint256 epochsPaid,,,) = agentPay(agent, pool, sc);

      require(epochsPaid == 0, "Should have exited from the pool");

      // check that the agent is no longer on administration
      vm.startPrank(IAuth(address(police)).owner());

      police.rmAgentFromAdministration(address(agent));

      assertEq(agent.administration(), address(0), "Agent Should not be on administration after paying up");
    }

    function testSetAgentDefaulted(uint256 rollFwdPeriod, uint256 borrowAmount) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      borrowAmount = bound(borrowAmount, WAD, stakeAmount);
      // helper includes assertions
      setAgentDefaulted(
        agent,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );
    }

    function testSetAdministrationNonAgentPolice(uint256 rollFwdPeriod) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

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

    function testRmAdministrationNonAgentPolice() public {
      uint256 rollFwdPeriod = police.defaultWindow() + 100;
      uint256 borrowAmount = WAD;

      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );

      // deal enough funds to the Agent so it can make a payment back to the Pool
      vm.deal(address(agent), borrowAmount * 4);

      SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

      // here we are exiting the pool by overpaying so much
      (,uint256 epochsPaid,,,) = agentPay(agent, pool, sc);

      require(epochsPaid == 0, "Should have exited from the pool");

      try police.rmAgentFromAdministration(address(agent)) {
        assertTrue(false, "only agent police owner operator should be able to call rmAgentFromAdministration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), Unauthorized.selector);
      }
    }

    function testSetAgentDefaultedNonAgentPolice(uint256 rollFwdPeriod) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      uint256 borrowAmount = WAD;
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      agentBorrow(agent, pool.id(), borrowCred);

      vm.roll(block.number + rollFwdPeriod);

      try police.setAgentDefaulted(address(agent)) {
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
      setAgentDefaulted(
        agent,
        police.defaultWindow() + 1,
        WAD,
        pool.id()
      );

      vm.startPrank(IAuth(address(police)).owner());
      police.prepareMinerForLiquidation(address(agent), liquidator, miner);

      // get the miner actor to ensure that the proposed owner on the miner is the liquidator
      assertEq(IMockMiner(idStore.ids(miner)).proposed(), liquidator, "Mock miner should have liquidator as its proposed owner");
    }

    function testSetAgentLiquidated() public {
      // helper contains assertions
      setAgentLiquidated(
        agent,
        police.defaultWindow() + 1,
        WAD,
        pool.id()
      );
    }

    function testDistributeLiquidatedFundsEvenSplit(
      uint256 rollFwdPeriod,
      uint256 borrowAmount,
      uint256 numPools,
      uint256 recoveredFunds
    ) public {
      address policeOwner = IAuth(address(police)).owner();
      IPool _pool;
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );
      uint256 agentID = agent.id();
      // borrow and stake amounts are split evenly among the pools
      numPools = bound(numPools, 1, police.maxPoolsPerAgent());

      borrowAmount = bound(borrowAmount, WAD * numPools, stakeAmount);

      recoveredFunds = bound(recoveredFunds, 1000, borrowAmount);

      for (uint8 i = 0; i < numPools; i++) {
        // create a pool and fund it with the proportionate stake amount
        _pool = createAndFundPool(stakeAmount / numPools, investor1);

        // borrow from the pool
        SignedCredential memory borrowCred = issueGenericBorrowCred(agentID, borrowAmount / numPools);
        agentBorrow(agent, _pool.id(), borrowCred);
      }

      uint256 balanceBefore = wFIL.balanceOf(address(_pool));

      // roll forward to the default window
      vm.roll(block.number + rollFwdPeriod);

      vm.startPrank(policeOwner);
      // set the agent in default
      police.setAgentDefaulted(address(agent));
      // liquidate the agent
      police.liquidatedAgent(address(agent));

      vm.deal(policeOwner, recoveredFunds);
      wFIL.deposit{value: recoveredFunds}();
      wFIL.approve(address(police), recoveredFunds);

      // distribute the recovered funds
      police.distributeLiquidatedFunds(agentID, recoveredFunds);
      uint256 balanceAfter = wFIL.balanceOf(address(_pool));

      // ensure the write down amount is correct:
      assertEq(balanceAfter - balanceBefore, recoveredFunds / numPools, "Pool should have received the correct amount of funds");

      Account memory account = AccountHelpers.getAccount(router, agent.id(), _pool.id());
      assertTrue(account.defaulted, "Agent should be defaulted");
      // Trying to distribute funds again should fail
      vm.deal(policeOwner, recoveredFunds);
      wFIL.deposit{value: recoveredFunds}();
      wFIL.approve(address(police), recoveredFunds);
      vm.expectRevert(abi.encodeWithSelector(AlreadyDefaulted.selector));
      police.distributeLiquidatedFunds(agentID, recoveredFunds);
      vm.stopPrank();
    }


    function testDistributeLiquidatedFundsThreePools(
      uint256 rollFwdPeriod,
      uint256 borrowAmount,
      uint256 recoveredFunds,
      uint256 poolOnePercent,
      uint256 poolTwoPercent,
      uint256 poolThreePercent
    ) public {
      uint256 numPools = 3;
      borrowAmount = bound(borrowAmount, WAD * numPools, stakeAmount);
      recoveredFunds = bound(recoveredFunds, 1000, borrowAmount);
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );
      poolOnePercent = bound(poolOnePercent, 1, WAD);
      poolTwoPercent = bound(poolTwoPercent, 1, WAD - poolOnePercent);
      poolThreePercent = WAD - poolOnePercent - poolTwoPercent;

      address policeOwner = IAuth(address(police)).owner();
      uint256 balanceAfter;
      IPool[] memory poolArray = new IPool[](numPools);
      uint256[] memory percentArray = new uint256[](numPools);
      uint256[] memory balanceArray = new uint256[](numPools);
      percentArray[0] = poolOnePercent;
      percentArray[1] = poolTwoPercent;
      percentArray[2] = poolThreePercent;

      for (uint8 i = 0; i < numPools; i++) {
        // create a pool and fund it with the proportionate stake amount
        poolArray[i] = createAndFundPool(stakeAmount, investor1);

        // borrow from the pool
        uint256 _borrowAmount = borrowAmount * percentArray[i] / WAD;
        vm.assume(_borrowAmount > WAD);
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), _borrowAmount);
        agentBorrow(agent, poolArray[i].id(), borrowCred);
        balanceArray[i] = wFIL.balanceOf(address(poolArray[i]));
      }
      // roll forward to the default window
      vm.roll(block.number + rollFwdPeriod);
      vm.startPrank(policeOwner);
      // set the agent in default
      police.setAgentDefaulted(address(agent));
      // liquidate the agent
      police.liquidatedAgent(address(agent));
      vm.stopPrank();
      vm.deal(policeOwner, recoveredFunds);
      vm.startPrank(policeOwner);
      wFIL.deposit{value: recoveredFunds}();
      wFIL.approve(address(police), recoveredFunds);
      vm.assume(recoveredFunds > WAD);
      // distribute the recovered funds
      police.distributeLiquidatedFunds(agent.id(), recoveredFunds);
      for (uint8 i = 0; i < numPools; i++) {
        balanceAfter = wFIL.balanceOf(address(poolArray[i]));
        // ensure the write down amount is correct:
        assertApproxEqAbs(balanceAfter - balanceArray[i], recoveredFunds * percentArray[i] / WAD, 5,  "Pool should have received the correct amount of funds");
        Account memory account = AccountHelpers.getAccount(router, agent.id(), poolArray[i].id());
        assertTrue(account.defaulted, "Agent should be defaulted");
      }
    }

    function testDistributeLiquidatedFundsFullRecovery(
      uint256 rollFwdPeriod,
      uint256 borrowAmount,
      uint256 recoveredFunds
    ) public {
      borrowAmount = bound(borrowAmount, WAD, stakeAmount);
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );
      vm.assume(recoveredFunds > WAD);

      address policeOwner = IAuth(address(police)).owner();
      uint256 balanceAfter;
      uint256 balanceBefore;
      uint256 interestOwed= getPenaltyOwed(borrowAmount, rollFwdPeriod);
      recoveredFunds = bound(recoveredFunds, borrowAmount, stakeAmount);
      agentBorrow(agent, pool.id(), borrowCred);
      balanceBefore = wFIL.balanceOf(address(pool));
      // roll forward to the default window
      vm.roll(block.number + rollFwdPeriod);
      vm.startPrank(policeOwner);
      // set the agent in default
      police.setAgentDefaulted(address(agent));
      // liquidate the agent
      police.liquidatedAgent(address(agent));
      vm.stopPrank();
      vm.deal(policeOwner, recoveredFunds);
      vm.startPrank(policeOwner);
      wFIL.deposit{value: recoveredFunds}();
      wFIL.approve(address(police), recoveredFunds);
      // distribute the recovered funds
      police.distributeLiquidatedFunds(agent.id(), recoveredFunds);
      Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
      assertTrue(account.defaulted, "Agent should be defaulted");
      balanceAfter = wFIL.balanceOf(address(pool));
      uint256 balanceChange = borrowAmount + interestOwed > recoveredFunds ? recoveredFunds : borrowAmount + interestOwed;
      assertEq(balanceAfter - balanceBefore, balanceChange,  "Pool should have received the correct amount of funds");
    }

    function getPenaltyOwed(uint256 amount, uint256 rollFwdPeriod) public view returns (uint256) {
      IRateModule rateModule = IRateModule(pool.rateModule());
      uint256 rate = rateModule.penaltyRate();
      uint256 _interestOwedPerEpoch = amount.mulWadUp(rate);
      // _interestOwedPerEpoch is mulWadUp by epochs (not WAD based), which cancels the WAD out for interestOwed
      return _interestOwedPerEpoch.mulWadUp(rollFwdPeriod);

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
        pool = createAndFundPool(
            stakeAmount,
            investor1
        );
        (agent, miner) = configureAgent(minerOwner);
        prevAgentAddr = address(agent);
    }

    function testUpgradeNoAuth() public {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
        agentFactory.upgradeAgent(prevAgentAddr);
    }

    function testUpgradeBasic() public {
        uint256 agentId = agent.id();
        address agentOwner = _agentOwner(agent);
        address agentOperator = _agentOperator(agent);
        IAgentFactory agentFactory = GetRoute.agentFactory(router);
        vm.prank(minerOwner);
        IAgent newAgent = IAgent(agentFactory.upgradeAgent(prevAgentAddr));
        assertEq(newAgent.id(), agentId);
        assertEq(_agentOwner(newAgent), agentOwner);
        assertEq(_agentOperator(newAgent), agentOperator);
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

      UpgradedAgentDeployer deployer = new UpgradedAgentDeployer();

      vm.prank(systemAdmin);
      IRouter(router).pushRoute(ROUTE_AGENT_DEPLOYER, address(deployer));

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
}

// contract AgentCollateralsTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address investor2 = makeAddr("INVESTOR_2");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");
//     string poolName = "FIRST POOL NAME";
//     uint256 baseInterestRate = 20e18;
//     uint256 stakeAmount;

//     IAgent agent;
//     uint64 miner;
//     IPool pool1;
//     IPool pool2;
//     IERC4626 pool46261;
//     IERC4626 pool46262;

//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;

//     uint256 borrowAmount = 10e18;

//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);

//         pool1 = createPool(
//             "TEST1",
//             "TEST1",
//             poolOperator,
//             2e18
//         );
//         pool46261 = IERC4626(address(pool1));

//         pool2 = createPool(
//             "TEST2",
//             "TEST2",
//             poolOperator,
//             2e18
//         );
//         pool46262 = IERC4626(address(pool2));
//         // investor1 stakes 10 FIL
//         vm.deal(investor1, 50e18);
//         stakeAmount = 20e18;
//         vm.startPrank(investor1);
//         wFIL.deposit{value: stakeAmount*2}();
//         wFIL.approve(address(pool1), stakeAmount);
//         wFIL.approve(address(pool2), stakeAmount);
//         pool46261.deposit(stakeAmount, investor1);
//         pool46262.deposit(stakeAmount, investor1);
//         vm.stopPrank();

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);

//         SignedCredential memory sc = issueGenericSC(address(agent));
//         agent.borrow(borrowAmount, pool1.id(), sc, sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         sc = issueGenericSC(address(agent));
//         agent.borrow(borrowAmount, pool2.id(), sc, sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         vm.stopPrank();
//     }

//     function testGetMaxWithdrawUnderLiquidity() public {
//         /*
//             issue a new signed cred to make Agent's financial situation look like this:
//             - qap: 10e18
//             - pool 1 borrow amount 10e18
//             - pool 2 borrow amount 10e18
//             - pool1 power token stake 5e18
//             - pool2 power token stake 5e18
//             - agent assets: 10e18
//             - agent liabilities: 8e18
//             - agent liquid balance: 10e18
//             the agent should be able to withdraw:
//             liquid balance + assets - liabilities - minCollateralValuePool1 - minCollateralValuePool2
//             (both pools require 10% of their totalBorrwed amount)
//         */

//         SignedCredential memory sc = issueSC(createCustomCredential(
//             address(agent),
//             signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             signedCred.vc.getExpectedDailyRewards(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             signedCred.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             8e18
//         ));

//         // expected withdraw amount is the agents liquidation value minus the min collateral of both pools
//         uint256 liquidationValue = agent.liquidAssets() + sc.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - sc.vc.getLiabilities(IRouter(router).getRoute(ROUTE_CRED_PARSER));
//         // the mock pool implementation returns 10% of totalBorrowed for minCollateral
//         Account memory account1 = AccountHelpers.getAccount(router, address(agent), pool1.id());
//         Account memory account2 = AccountHelpers.getAccount(router, address(agent), pool2.id());

//         uint256 minCollateralPool1 = pool1.implementation().minCollateral(account1, sc.vc);
//         uint256 minCollateralPool2 = pool2.implementation().minCollateral(account2, sc.vc);
//         uint256 expectedWithdrawAmount = liquidationValue - minCollateralPool1 - minCollateralPool2;

//         uint256 withdrawAmount = agent.maxWithdraw(sc);
//         assertEq(withdrawAmount, expectedWithdrawAmount, "Wrong withdraw amount");
//     }

//     function testWithdrawUnderMax(uint256 withdrawAmount) public {
//         vm.assume(withdrawAmount < agent.maxWithdraw(signedCred));

//         address receiver = makeAddr("RECEIVER");

//         assertEq(receiver.balance, 0, "Receiver should have no balance");
//         vm.startPrank(minerOwner);
//         agent.withdraw(receiver, withdrawAmount, issueGenericSC(address(agent)));
//         vm.stopPrank();
//         assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
//     }

//     function testWithdrawMax() public {
//         uint256 withdrawAmount = agent.maxWithdraw(signedCred);

//         address receiver = makeAddr("RECEIVER");

//         assertEq(receiver.balance, 0, "Receiver should have no balance");
//         vm.startPrank(minerOwner);
//         agent.withdraw(receiver, withdrawAmount, issueGenericSC(address(agent)));
//         assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
//         vm.stopPrank();
//     }

//     function testWithdrawTooMuch(uint256 overWithdrawAmt) public {
//         address receiver = makeAddr("RECEIVER");
//         uint256 withdrawAmount = agent.maxWithdraw(signedCred);
//         vm.assume(overWithdrawAmt > withdrawAmount);
//         vm.startPrank(minerOwner);
//         try agent.withdraw(receiver, withdrawAmount * 2, issueGenericSC(address(agent))) {
//             assertTrue(false, "Should not be able to withdraw more than the maxwithdraw amount");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }
//         vm.stopPrank();
//     }

//     function testMaxWithdrawToLiquidityLimit() public {
//         uint256 LIQUID_AMOUNT = 10000;
//         uint64[] memory _miners = new uint64[](1);
//         uint256[] memory _amounts = new uint256[](1);
//         // push funds to the miner so that the agent's liquid balance is less than the withdrawAmount
//         _amounts[0] = agent.liquidAssets() - LIQUID_AMOUNT;
//         _miners[0] = uint64(miner);
//         vm.startPrank(minerOwner);
//         agent.pushFunds(_miners, _amounts, issueGenericSC(address(agent)));

//         uint256 withdrawAmount = agent.maxWithdraw(issueGenericSC(address(agent)));

//         assertEq(withdrawAmount, LIQUID_AMOUNT, "max withdraw should be the liquidity limit");
//         vm.stopPrank();
//     }

//     function testRemoveMiner() public {
//         assertEq(agent.minersCount(), 1, "Agent should have 1 miner");
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));
//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // in this example, remove a miner that has no power or assets
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             0,
//             0,
//             0,
//             0
//         ));

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         assertEq(agent.minersCount(), 2, "Agent should have 2 miners");
//         assertEq(agent.miners(1), newMiner, "Miner should be added to the agent");
//         vm.startPrank(minerOwner);
//         agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred);
//         assertEq(agent.hasMiner(newMiner), false, "Miner should be removed");
//         vm.stopPrank();
//     }

//     function testRemoveMinerWithTooMuchPower(uint256 powerAmount) public {
//         vm.assume(powerAmount <= signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));

//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // in this example, remove a miner that contributes all the borrowing power
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             0,
//             0,
//             0
//         ));

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         vm.startPrank(minerOwner);
//         // TODO: replace with proper expect revert
//         try agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred) {
//             assertTrue(false, "Should not be able to remove a miner with too much power");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }
//     }

//     function testRemoveMinerWithTooLargeLiquidationValue() public {
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));
//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // transfer out the balance of the agent to reduce the total collateral of the agent
//         address recipient = makeAddr("RECIPIENT");
//         uint256 withdrawAmount = agent.maxWithdraw(issueGenericSC(address(agent)));
//         vm.startPrank(minerOwner);
//         agent.withdraw(recipient, withdrawAmount, issueGenericSC(address(agent)));

//         // in this example, remove a miner that contributes all the assets
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             0,
//             0,
//             signedCred.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             0
//         ));
//         vm.stopPrank();

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         vm.startPrank(minerOwner);

//         try agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred) {
//             assertTrue(false, "Should not be able to remove a miner with too much liquidation value");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }

//         vm.stopPrank();
//     }
// }

// contract AgentTooManyPoolsTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");

//     IAgent agent;
//     uint64 miner;

//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;

//     uint256 stakeAmountPerPool = 2e18;
//     uint256 borrowAmountPerPool = 1e18;
//     uint256 maxPools;
//     uint256 powerTokenStakePerPool;

//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
//         // investor1 stakes 10 FIL
//         vm.deal(investor1, 50e18);
//         vm.prank(investor1);
//         wFIL.deposit{value: 50e18}();

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//         vm.stopPrank();
//         maxPools = GetRoute.agentPolice(router).maxPoolsPerAgent();
//         powerTokenStakePerPool = signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / (maxPools * 2);

//         for (uint256 i = 0; i <= maxPools; i++) {
//             string memory poolName = Strings.toString(i);
//             IPool _pool = createPool(
//                 poolName,
//                 poolName,
//                 poolOperator,
//                 2e18
//             );

//             _deposit(_pool);

//             vm.startPrank(minerOwner);
//             agent.borrow(
//                 borrowAmountPerPool,
//                 _pool.id(),
//                 issueGenericSC(address(agent)),
//                 powerTokenStakePerPool
//             );
//             vm.stopPrank();
//         }
//     }

//     function testTooManyPoolsBorrow() public {
//         // create maxPool + 1 pool
//         IPool pool = createPool(
//             "Too manyith pool",
//             "OOPS",
//             poolOperator,
//             2e18
//         );

//         _deposit(pool);

//         vm.startPrank(minerOwner);
//         try agent.borrow(
//             borrowAmountPerPool,
//             pool.id(),
//             issueGenericSC(address(agent)),
//             powerTokenStakePerPool
//         ) {
//             assertTrue(false, "Agent should not be able to borrow from 11 pools");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), BadAgentState.selector);
//         }
//         vm.stopPrank();
//     }

//     function _deposit(IPool pool) internal {
//         vm.startPrank(investor1);
//         wFIL.approve(address(pool), stakeAmountPerPool);
//         pool.deposit(stakeAmountPerPool, investor1);
//         vm.stopPrank();
//     }
// }

contract AgentBeneficiaryTest is BaseTest {
  address ownerAddr = makeAddr("OWNER");
  IAgent agent;

  function setUp() public {
    (agent, ) = configureAgent(ownerAddr);
  }

  function testChangeBeneficiary(
    address beneficiary,
    uint256 quota,
    uint256 expiration
  ) public {
    changeBeneficiary(agent, beneficiary, quota, expiration);
  }

  function testAcceptBeneficiary(
    address beneficiary,
    uint256 expiration,
    uint256 quota
  ) public {
    configureBeneficiary(agent, beneficiary, expiration, quota);
  }

  // this is a hardcoded parameter test basd on a single failing fuzz test
  function testAcceptBeneficiaryFailedFuzz() public {
    address beneficiary = 0xDf6b52E30EC5230ff26a6ac94d92e782720Aa4bD;
    uint256 expiration = 1322;
    uint256 quota = 12270;

    configureBeneficiary(agent, beneficiary, expiration, quota);
  }

  function testWithdrawalBadSender(
    string calldata receipientSeed,
    uint256 withdrawAmount,
    uint256 balance
  ) public {
    balance = bound(balance, withdrawAmount, type(uint256).max);
    uint256 balanceBefore = address(ownerAddr).balance;
    address recipient = makeAddr(receipientSeed);
    vm.deal(address(agent), balance);
    vm.assume(recipient != ownerAddr);
    vm.startPrank(recipient);
    SignedCredential memory sc = issueWithdrawCred(agent.id(), withdrawAmount, emptyAgentData());
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    agent.withdraw(recipient, sc);
  }

  function testBeneficiaryWithdrawal(
    string calldata beneficiarySeed,
    string calldata receipientSeed,
    uint256 expiration,
    uint256 quota,
    uint256 withdrawAmount,
    uint256 balance
  ) public {
    // make sure the beneficiary is active
    expiration = bound(expiration, block.number + 100, type(uint256).max);
    quota = bound(quota, DUST, type(uint256).max);
    address beneficiary = makeAddr(beneficiarySeed);
    address recipient = makeAddr(receipientSeed);
    configureBeneficiary(agent, beneficiary, expiration, quota);

    balance = bound(balance, withdrawAmount, type(uint256).max);

    vm.assume(beneficiary != address(0));
    vm.deal(address(agent), balance);

    vm.startPrank(beneficiary);
    SignedCredential memory sc = issueWithdrawCred(agent.id(), withdrawAmount, emptyAgentData());
    agent.withdraw(recipient, sc);
    vm.stopPrank();

    uint256 withdrawnAmount = withdrawAmount > quota ? quota : withdrawAmount;
    assertEq(address(recipient).balance, withdrawnAmount);
    assertEq(balance - address(agent).balance, withdrawnAmount);
    assertEq(agent.beneficiary().active.usedQuota, withdrawnAmount);
    // If there is balance left after the beneficiary withdraws, the owner should be able to withdraw it
    if(withdrawAmount > quota) {
      vm.startPrank(ownerAddr);
      uint256 ownerWithdraw = withdrawAmount - quota;
      sc = issueWithdrawCred(agent.id(), ownerWithdraw, emptyAgentData());
      agent.withdraw(recipient, sc);
      assertEq(agent.beneficiary().active.usedQuota, quota, "used quota");
    }
    // Once the owner and beneficiary have withdrawn as much as they both can all of the withdrawAmountshould be accounted for
    assertEq(address(recipient).balance, withdrawAmount, "beneficiary balance");
    assertEq(balance - address(agent).balance, withdrawAmount, "agent balance");
  }

  function testOwnerWithdrawal(
    string calldata receipientSeed,
    uint256 withdrawAmount,
    uint256 balance
  ) public {
    balance = bound(balance, withdrawAmount, type(uint256).max);
    uint256 balanceBefore = address(ownerAddr).balance;
    address recipient = makeAddr(receipientSeed);
    vm.deal(address(agent), balance);

    vm.startPrank(ownerAddr);
    SignedCredential memory sc = issueWithdrawCred(agent.id(), withdrawAmount, emptyAgentData());
    agent.withdraw(recipient, sc);

    assertEq(address(recipient).balance - balanceBefore, withdrawAmount);
    assertEq(balance - address(agent).balance, withdrawAmount);
  }

  function testOwnerWithdrawalWhileBeneficiary(
    string calldata beneficiarySeed,
    string calldata receipientSeed,
    uint256 expiration,
    uint256 quota,
    uint256 withdrawAmount,
    uint256 balance
  ) public {
    // make sure the beneficiary is active
    expiration = bound(expiration, block.number + 100, type(uint256).max);
    quota = bound(quota, DUST, type(uint256).max);
    address beneficiary = makeAddr(beneficiarySeed);
    address recipient = makeAddr(receipientSeed);
    vm.assume(beneficiary != recipient);
    configureBeneficiary(agent, beneficiary, expiration, quota);
    balance = bound(balance, withdrawAmount, type(uint256).max);
    uint256 balanceBefore = address(beneficiary).balance;
    vm.deal(address(agent), balance);

    vm.startPrank(ownerAddr);
    SignedCredential memory sc = issueWithdrawCred(agent.id(), withdrawAmount, emptyAgentData());
    vm.expectRevert(abi.encodeWithSelector(Unauthorized.selector));
    agent.withdraw(recipient, sc);
    agent.withdraw(beneficiary, sc);

    uint256 withdrawnAmount = withdrawAmount > quota ? quota : withdrawAmount;
    assertEq(address(beneficiary).balance - balanceBefore, withdrawnAmount);
    assertEq(balance - address(agent).balance, withdrawnAmount);
  }
}
