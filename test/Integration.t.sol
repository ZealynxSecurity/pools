// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./BaseTest.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";

// This contract contains 1 test and a ton of helper funcs to make assertions
contract IntegrationTest is BaseTest {

    error InsufficientFunds();
    error AccountDNE();

    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

    IAgent agent;
    uint256 agentID;
    uint64 miner;
    address minerAddr;
    IPool pool;
    uint256 poolID;
    IPoolToken iFIL;

    address investor = makeAddr("INVESTOR");
    address minerOwner = makeAddr("MINER_OWNER");

    // single investor, single borrower
    function testAllActions(
      uint256 stakeAmount,
      uint256 borrowAmount,
      uint256 payAmount,
      uint256 pushAmount,
      uint256 minerRewardAmount,
      uint256 rollFwdAmnt
    ) public {
      stakeAmount = bound(stakeAmount, 0, MAX_FIL);
      borrowAmount = bound(borrowAmount, 0, MAX_FIL);
      payAmount = bound(payAmount, 0, MAX_FIL);
      pushAmount = bound(pushAmount, 0, MAX_FIL);
      minerRewardAmount = bound(minerRewardAmount, 0, MAX_FIL);
      rollFwdAmnt = bound(rollFwdAmnt, 0, EPOCHS_IN_YEAR);

      pool = createPool();
      poolID = pool.id();
      iFIL = pool.liquidStakingToken();

      (agent, miner) = configureAgent(minerOwner);
      agentID = agent.id();
      minerAddr = idStore.ids(miner);

      depositAndAssert(stakeAmount);

      borrowAndAssert(borrowAmount);

      pushAndAssert(pushAmount);

      pullAndAssert(minerRewardAmount);

      vm.roll(block.number + rollFwdAmnt);

      payAndAssert(payAmount);
    }

    function depositAndAssert(uint256 stakeAmount) internal {
      // just make sure we don't run out of funds
      vm.deal(investor, MAX_FIL * 3);
      vm.startPrank(investor);

      // first we put WAD worth of FIL in the pool to block inflation attacks
      pool.deposit{value: WAD}(investor);

      // here we split the stakeAmount into wFIL and FIL for testing purposes
      wFIL.deposit{value: stakeAmount}();
      wFIL.approve(address(pool), stakeAmount);

      uint256 investorFILBalStart = investor.balance;
      uint256 investorWFILBalStart = wFIL.balanceOf(investor);
      uint256 investorIFILBalStart = iFIL.balanceOf(investor);
      uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

      assertPegInTact(pool);

      // check wFIL invariant
      assertEq(investorWFILBalStart + poolWFILBalStart, wFIL.totalSupply(), "Investor + pool should hold all WFIL at start");

      // ensure can't stake 0
      if (stakeAmount == 0) {
        vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
        pool.deposit{value: stakeAmount}(investor);
        
        vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
        pool.deposit(stakeAmount, investor);

        assertEq(investorWFILBalStart, wFIL.balanceOf(investor), "Investor should have same WFIL balance");
        assertEq(investorFILBalStart, investor.balance, "Investor should have same FIL balance");
        assertEq(investorIFILBalStart, iFIL.balanceOf(investor), "Investor should have same iFIL balance");

        // ensure can't deposit more than you have
        vm.expectRevert();
        pool.deposit{value: investor.balance * 2}(investor);

        wFIL.approve(address(pool), MAX_FIL + DUST);
        vm.expectRevert();
        pool.deposit(stakeAmount, investor);

        assertEq(wFIL.balanceOf(address(pool)), poolWFILBalStart, "Pool should not increase any WFIL balance");
      } else {
        // ensure 1:1 iFIL to FIL received
        uint256 sharesFirstDeposit = pool.deposit{value: stakeAmount}(investor);
        // price 1:1
        assertEq(sharesFirstDeposit, stakeAmount, "Investor should have received stake amount of shares after first deposit 1");
        assertEq(sharesFirstDeposit, iFIL.balanceOf(investor) - investorIFILBalStart, "Investor should have received stake amount of shares after first deposit 2");
        // should not have withdrawn wFIL yet
        assertEq(investorWFILBalStart, wFIL.balanceOf(investor), "Investor should have the same amount of WFIL after depositing FIL");
        // should have withdrawn FIL
        assertEq(investorFILBalStart - stakeAmount, investor.balance, "Investor should have FIL - stake balance in FIL");
        uint256 sharesSecondDeposit = pool.deposit(stakeAmount, investor);
        assertEq(sharesSecondDeposit, stakeAmount, "Investor should have received stake amount of shares after second deposit 1");
        assertEq(sharesSecondDeposit + sharesFirstDeposit, iFIL.balanceOf(investor) - investorIFILBalStart, "Investor should have received stake amount of shares after second deposit 2");
        // should have withdrawn wFIL now
        assertEq(investorWFILBalStart - stakeAmount, wFIL.balanceOf(investor), "Investor should have the same amount of WFIL after depositing FIL");
        assertEq(wFIL.totalSupply(), wFIL.balanceOf(address(pool)) + wFIL.balanceOf(investor), "Pool should have stakeAmount of WFIL balance");
        assertEq(wFIL.balanceOf(address(pool)) - poolWFILBalStart, stakeAmount * 2, "Pool should have received stakeAmount of WFIL balance 2");
      }

      uint256 investorIFILBalEnd = iFIL.balanceOf(investor);
      assertEq(pool.convertToAssets(investorIFILBalEnd), (stakeAmount * 2) + investorIFILBalStart, "Investor should have stakeAmount worth of shares");
      assertEq(pool.convertToShares(stakeAmount * 2), investorIFILBalEnd - investorIFILBalStart, "Investor should have stakeAmount worth of shares 2");
      assertPegInTact(pool);
      testInvariants(pool, "depositAndAssert");
      vm.stopPrank();
    }

    function borrowAndAssert(uint256 borrowAmount) internal {
      vm.startPrank(_agentOwner(agent));

      testInvariants(pool, "pre borrow assertion");

      uint256 investorIFILBalStart = iFIL.balanceOf(investor);
      uint256 agentWFILBalStart = wFIL.balanceOf(address(agent));

      SignedCredential memory borrowCred = issueGenericBorrowCred(agentID, borrowAmount);
      // must meet the minimum borrow amount
      if (borrowAmount < WAD) {
        vm.expectRevert(InvalidParams.selector);
        agent.borrow(poolID, borrowCred);
        assertEq(agentWFILBalStart, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
      } else if (borrowAmount > pool.totalBorrowableAssets()) {
        vm.expectRevert(InsufficientLiquidity.selector);
        agent.borrow(poolID, borrowCred);
        assertEq(agentWFILBalStart, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
      } else {
        // borrow should work
        agent.borrow(poolID, borrowCred);
        assertEq(agentWFILBalStart + borrowAmount, wFIL.balanceOf(address(agent)), "Agent should have increased WFIL balance by borrowAmount");
      }

      // make sure the investor's iFIL balance and value is correct
      assertPegInTact(pool);
      testInvariants(pool, "post borrow assertion");
      assertEq(investorIFILBalStart, iFIL.balanceOf(investor), "Investor should have same iFIL balance");
      assertEq(pool.convertToAssets(investorIFILBalStart), investorIFILBalStart, "Investor's iFIL should still be worth the same amount as before");
      // wfil invariant
      assertEq(wFIL.totalSupply(), wFIL.balanceOf(address(pool)) + wFIL.balanceOf(investor) + wFIL.balanceOf(address(agent)), "WFIL invariant should pass");
      vm.stopPrank();
    }

    function pushAndAssert(uint256 pushAmount) internal {
      SignedCredential memory pushCred = issuePushFundsCred(agentID, miner, pushAmount);

      vm.startPrank(_agentOperator(agent));

      uint256 minerFILBalStart = minerAddr.balance;
      uint256 minerWFILBalStart = wFIL.balanceOf(minerAddr);
      uint256 agentFILBalStart = address(agent).balance;
      uint256 agentWFILBalStart = wFIL.balanceOf(address(agent));

      assertEq(agentFILBalStart, 0, "Agent should not have any FIL");
      assertEq(minerFILBalStart, 0, "Miner should not have any FIL");
      assertEq(minerWFILBalStart, 0, "Miner should not have any WFIL");

      if (pushAmount > agentWFILBalStart) {
        // can't afford the push
        vm.expectRevert(InsufficientFunds.selector);
        agent.pushFunds(pushCred);
        assertEq(agentFILBalStart, 0, "Agent should not have any FIL");
        assertEq(minerFILBalStart, 0, "Miner should not have any FIL");
        assertEq(minerWFILBalStart, 0, "Miner should not have any WFIL");
        assertEq(agentWFILBalStart, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
      } else {
        agent.pushFunds(pushCred);
        assertEq(agentFILBalStart, address(agent).balance, "Agent's FIL balance should not changed");
        assertEq(minerAddr.balance, minerFILBalStart + pushAmount, "Miner's FIL bal should increase by push amount");
        assertEq(wFIL.balanceOf(minerAddr), 0, "Miner should not have any WFIL");
        assertEq(agentWFILBalStart - pushAmount, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
      }

      assertPegInTact(pool);
      testInvariants(pool, "pushAndAssert");

      vm.stopPrank();
    }

    function pullAndAssert(uint256 pullAmount) internal {
      SignedCredential memory pullCred = issuePullFundsCred(agentID, miner, pullAmount);
      vm.startPrank(_agentOperator(agent));

      uint256 minerFILBalStart = minerAddr.balance;
      uint256 agentFILBalStart = address(agent).balance;
      uint256 agentWFILBalStart = wFIL.balanceOf(address(agent));

      if (minerFILBalStart < pullAmount) {
        // this means send max
        agent.pullFunds(pullCred);
        assertEq(minerAddr.balance, 0, "Miner should not have any FIL");
        assertEq(agentFILBalStart + minerFILBalStart, address(agent).balance, "Agent's FIL balance should have increased by pullAmount1");
      } else {
        agent.pullFunds(pullCred);
        assertEq(minerAddr.balance, minerFILBalStart - pullAmount, "Miner should have drawn down pullAmount of FIL");
        assertEq(agentFILBalStart + pullAmount, address(agent).balance, "Agent's FIL balance should have increased by pullAmount");
      }

      assertEq(agentWFILBalStart, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
      assertEq(wFIL.balanceOf(minerAddr), 0, "Miner should not have any WFIL");
      assertPegInTact(pool);
      testInvariants(pool, "pullAndAssert");

      vm.stopPrank();
    }

    function payAndAssert(uint256 payAmount) internal {
      SignedCredential memory payCred = issueGenericPayCred(agentID, payAmount);
      vm.startPrank(_agentOperator(agent));

      Account memory account = AccountHelpers.getAccount(router, address(agent), poolID);

      uint256 epochsOwed = block.number - account.epochsPaid;

      uint256 interestPerEpoch = account.principal.mulWadUp(
        pool.getRate(payCred.vc)
      );

      bool underPaid = payAmount * WAD < interestPerEpoch;
      bool paidMoreThanAvail = payAmount > agent.liquidAssets();
      bool exists = account.exists();

      bool invalidPmt = underPaid || paidMoreThanAvail || !exists;

      if (invalidPmt) {
        assertInvalidPayment(underPaid, paidMoreThanAvail, exists, payCred);
      } else {
        assertValidPayment(payAmount, interestPerEpoch, epochsOwed, account, payCred);
      }

      vm.stopPrank();
    }

    function assertInvalidPayment(
      bool underPaid, 
      bool paidMoreThanAvail, 
      bool exists, 
      SignedCredential memory sc
    ) internal {
        uint256 agentFILBalStart = address(agent).balance;
        uint256 agentWFILBalStart = wFIL.balanceOf(address(agent));
        uint256 poolFILBalStart = address(pool).balance;
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        if (paidMoreThanAvail) {
          vm.expectRevert(InsufficientFunds.selector);
        } else if (underPaid) {
          vm.expectRevert(InvalidParams.selector);
        } else if (!exists) {
          vm.expectRevert(AccountDNE.selector);
        }
        agent.pay(poolID, sc);

        assertEq(agentFILBalStart, address(agent).balance, "Agent's FIL balance should not changed");
        assertEq(agentWFILBalStart, wFIL.balanceOf(address(agent)), "Agent should have same WFIL balance");
        assertEq(poolFILBalStart, address(pool).balance, "Pool's FIL balance should not changed");
        assertEq(poolWFILBalStart, wFIL.balanceOf(address(pool)), "Pool should have same WFIL balance");

        assertPegInTact(pool);
        testInvariants(pool, "assertInvalidPayment");
    }

    function assertValidPayment(
      uint256 payAmount,
      uint256 interestPerEpoch,
      uint256 epochsOwed,
      Account memory prePayAccount,
      SignedCredential memory payCred
    ) internal {
        uint256 interestOwed = interestPerEpoch.mulWadUp(epochsOwed);

        uint256 iFILtoFILStart = pool.convertToAssets(iFIL.balanceOf(investor));
        uint256 FILtoIFILStart = pool.convertToShares(WAD);
        uint256 agentLiquidAssets = agent.liquidAssets();
        uint256 poolFILBalStart = address(pool).balance;
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));
        // valid payment
        agent.pay(poolID, payCred);
        Account memory postPayAccount = AccountHelpers.getAccount(router, address(agent), poolID);
        // assertions
        uint256 feeBasis;
        uint256 expIFILAppreciation;
        if (payAmount < interestOwed) {
          (feeBasis, expIFILAppreciation) = assertInterestOnlyPayment(payAmount, interestPerEpoch, prePayAccount, postPayAccount);
        } else {
          (feeBasis, expIFILAppreciation) = assertPrincipalAndInterestPayment(payAmount, interestOwed, prePayAccount, postPayAccount);
        }
        // pay invariants
        assertEq(
          pool.convertToAssets(iFIL.balanceOf(investor)) - iFILtoFILStart, 
          expIFILAppreciation - feeBasis.mulWadUp(GetRoute.poolRegistry(router).treasuryFeeRate()),
          "Investor's IFIL value should have increased by pay amount"
        );
        uint256 FILtoIFIL = pool.convertToShares(WAD);
        // we should be getting less than WAD shares because of the payment
        assertLt(
          FILtoIFIL,
          FILtoIFILStart,
          "Share price should increase"
        );
        assertEq(agentLiquidAssets - payAmount, agent.liquidAssets(), "Agent's liquid assets should have been reduced by pay amount");
        assertEq(poolWFILBalStart + payAmount, wFIL.balanceOf(address(pool)), "Pool's WFIL bal should increase by payment");
        assertEq(poolFILBalStart, 0, "Pool's FIL bal should not change");
        testInvariants(pool, "assertValidPayment");
    }

    function assertInterestOnlyPayment(
      uint256 payAmount, 
      uint256 interestPerEpoch, 
      Account memory prePayAccount, 
      Account memory postPayAccount
    ) internal returns (uint256 feeBasis, uint256 expIFILAppreciation) {
        assertEq(payAmount.divWadDown(interestPerEpoch) + prePayAccount.epochsPaid, postPayAccount.epochsPaid, "Account epochsPaid should have been updated properly");
        assertLt(postPayAccount.epochsPaid, block.number, "Epochs paid should not be more than current for a partial interest payment");
        assertGt(postPayAccount.epochsPaid, prePayAccount.epochsPaid, "Epochs paid should have moved up");
        testInvariants(pool, "assertInterestOnlyPayment");

        // here we should assume that the entire payAmount should be realized by the investor's IFIL minus treasury fees
        // so feeBasis and expIFILAppreciation are both applied on the full payAmount
        return (payAmount, payAmount);
    }

    function assertPrincipalAndInterestPayment(
      uint256 payAmount,
      uint256 interestOwed,
      Account memory prePayAccount,
      Account memory postPayAccount
    ) internal returns (uint256 feeBasis, uint256 expIFILAppreciation) {
        uint256 totalOwed = interestOwed + prePayAccount.principal;
        if (payAmount > totalOwed) {
          // full exit
          assertEq(postPayAccount.principal, 0, "Principal should be reset");
          assertEq(postPayAccount.epochsPaid, 0, "Epochs paid should be reset");  
        } else {
          uint256 principalPayment = payAmount - interestOwed;
          assertEq(postPayAccount.principal, prePayAccount.principal - principalPayment, "Principal should have been reduced by principalPaid");
          assertEq(postPayAccount.epochsPaid, block.number, "Epochs paid should have been updated");
        }

        testInvariants(pool, "assert principal and interest payment");

        // here we should assume that the entire interestOwed should be realized by the investor's IFIL minus treasury fees
        // so feeBasis and expIFILAppreciation are both applied on the full interestOwed
        return (interestOwed, interestOwed);
    }
}
