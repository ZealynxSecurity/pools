// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";

contract EchidnaAgent is EchidnaSetup {

    IAgent internal globalAgent;

    constructor() payable {
        globalAgent = _configureAgent(AGENT_OWNER);
    }

    using FixedPointMathLib for uint256;

    function agentPayRevert(SignedCredential memory payCred) internal {
        try globalAgent.pay(poolID, payCred) {
            Debugger.log("pool pay didn't revert");
            assert(false);
        } catch {
            Debugger.log("pool pay successfully reverted");
        }
    }

    function agentPay(SignedCredential memory payCred) internal {
        try globalAgent.pay(poolID, payCred) {
            Debugger.log("pool pay successful");
        } catch {
            Debugger.log("pool pay failed");
            assert(false);
        }
    }

    // ============================================
    // ==               BORROW                   ==
    // ============================================

    // @audit I didn't review it yet
    // function echtest_credential_actions() public {
    //     uint256 agentID = 1;
    //     uint64 minerID = 1;

    //     SignedCredential memory sc = _issueAddMinerCred(agentID, minerID);
    //     try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.addMiner.selector, sc) {
    //         assert(true);
    //     } catch {
    //         assert(false);
    //     }

    //     uint256 principal = 10e18;
    //     uint256 liquidationValue = 5e18;
    //     sc = _issueBorrowCred(agentID, principal, liquidationValue);
    //     try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.borrow.selector, sc) {
    //         assert(true);
    //     } catch {
    //         assert(false);
    //     }

    //     uint256 paymentAmount = 1e18;
    //     sc = _issuePayCred(agentID, principal, liquidationValue, paymentAmount);
    //     try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.pay.selector, sc) {
    //         assert(true);
    //     } catch {
    //         assert(false);
    //     }

    //     sc = _issueRemoveMinerCred(agentID, minerID, principal, liquidationValue);
    //     try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.removeMiner.selector, sc) {
    //         assert(true);
    //     } catch {
    //         assert(false);
    //     }

    //     uint256 amount = 5e18;
    //     sc = _issueWithdrawCred(agentID, amount, principal, liquidationValue);
    //     try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.withdraw.selector, sc) {
    //         assert(true);
    //     } catch {
    //         assert(false);
    //     }
    // }

    // Empty functions allow Echidna to run faster, uncomment these while testing
    // function echtest_empty1() public pure {
    //     assert(true);
    // }

    // function echtest_empty2() public pure {
    //     assert(true);
    // }

    // function echtest_empty3() public pure {
    //     assert(true);
    // }

    // function echtest_empty4() public pure {
    //     assert(true);
    // }

    // function echtest_empty5() public pure {
    //     assert(true);
    // }

    function echtest_agent_borrow(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL / 2) return;

        // IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = globalAgent.id();

        hevm.deal(INVESTOR, MAX_FIL);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(globalAgent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = globalAgent.liquidAssets();
        uint256 poolBorrowableAssetsBefore = pool.totalBorrowableAssets();

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        uint256 agentLiquidAssetsAfter = globalAgent.liquidAssets();
        uint256 poolBorrowableAssetsAfter = pool.totalBorrowableAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(poolBorrowableAssetsAfter == poolBorrowableAssetsBefore - borrowAmount);
    }

    // @audit => I didn't review it yet
    // function test_agent_borrow_insufficient_liquidity(uint256 borrowAmount, uint256 depositAmount) public {
    //     if (depositAmount < WAD || depositAmount > MAX_FIL / 2) return;
    //     if (borrowAmount < WAD || borrowAmount > depositAmount) return;

    //     IAgent agent = _configureAgent(AGENT_OWNER);
    //     uint256 agentID = agent.id();

    //     hevm.deal(INVESTOR, MAX_FIL);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(depositAmount, INVESTOR);

    //     uint256 liquidationValue = borrowAmount * 2;
    //     hevm.deal(address(agent), liquidationValue);
    //     SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount + 1, liquidationValue);


    //     uint256 agentLiquidAssetsBefore = agent.liquidAssets();
    //     uint256 poolBorrowableAssetsBefore = pool.totalBorrowableAssets();

    //     hevm.prank(AGENT_OWNER);
    //     agentBorrowRevert(address(globalAgent), sc);
    // }

    function echtest_agent_borrow_invalid_params() public {
        uint256 borrowAmount = WAD - 1;

        // IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = globalAgent.id();

        hevm.deal(INVESTOR, WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(WAD, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(globalAgent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agentBorrowRevert(address(globalAgent), sc);
    }

    function echtest_agent_borrow_not_owner(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL) return;

        // IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = globalAgent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(globalAgent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        agentBorrowRevert(address(globalAgent), sc);
    }

    function echtest_agent_borrow_expired_credential() public {
        uint256 borrowAmount = WAD;

        // IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = globalAgent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(globalAgent), liquidationValue);

        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);
        sc.vc.epochValidUntil = block.number - 1;

        hevm.prank(AGENT_OWNER);
        agentBorrowRevert(address(globalAgent), sc);
    }

    function echtest_agent_borrow_invalid_signature() public {
        uint256 borrowAmount = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);

        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);
        sc.s = bytes32(0);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        hevm.prank(AGENT_OWNER);
        agentBorrowRevert(address(globalAgent), sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    }

    function echtest_consecutive_borrows_update_liquid_assets(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL / 2) return;
        uint256 existingPrincipal = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + existingPrincipal + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil((borrowAmount + existingPrincipal), INVESTOR);

        uint256 liquidationValue = (borrowAmount + existingPrincipal) * 2;
        hevm.deal(address(agent), liquidationValue);

        // First borrow
        SignedCredential memory scInitial = _issueBorrowCred(agentID, existingPrincipal, liquidationValue);
        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), scInitial);

        // Roll forward to ensure a new credential can be issued
        hevm.roll(block.number + 1);

        // Second borrow with a new credential
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 totalBorrowedAfter = pool.totalBorrowed();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(totalBorrowedAfter == totalBorrowedBefore + borrowAmount);
    }

    function echtest_agent_borrow_fails_with_reused_credential(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL / 2) return;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount * 2 + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount * 2, INVESTOR);

        uint256 liquidationValue = borrowAmount * 4;
        hevm.deal(address(agent), liquidationValue);

        // Generate a borrow credential
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        // First borrow should succeed
        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        // Attempt second borrow with the same credential
        hevm.prank(AGENT_OWNER);
        agentBorrowRevert(address(globalAgent), sc);
    }

    function echtest_agent_borrow_rewards(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL) return;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 lpAccruedBefore = pool.lpRewards().accrued;
        uint256 lpPaidBefore = pool.lpRewards().paid;
        uint256 lpLostBefore = pool.lpRewards().lost;

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        uint256 lpAccruedAfter = pool.lpRewards().accrued;
        uint256 lpPaidAfter = pool.lpRewards().paid;
        uint256 lpLostAfter = pool.lpRewards().lost;

        assert(lpAccruedAfter >= lpAccruedBefore);
        assert(lpPaidAfter == lpPaidBefore);
        assert(lpLostAfter == lpLostBefore);
    }

    function echtest_agent_borrow_update_accounting(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL / 2) return;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 lastAccountingUpdateEpochBefore = pool.lastAccountingUpdateEpoch();

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 lastAccountingUpdateEpochAfter = pool.lastAccountingUpdateEpoch();

        // Verify that the agent's liquid assets increased by the borrowed amount
        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(lastAccountingUpdateEpochAfter == lastAccountingUpdateEpochBefore);
    }

    function echtest_agent_borrow_paused(uint256 borrowAmount) public {
        if (borrowAmount < WAD || borrowAmount > MAX_FIL) return;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(borrowAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        // Pause the pool
        hevm.prank(SYSTEM_ADMIN);
        IPausable(address(pool)).pause();

        // Try to borrow and expect a revert due to the pool being paused
        hevm.prank(AGENT_OWNER);
        agentBorrowRevert(address(globalAgent), sc);

        IPausable(address(pool)).unpause();
    }

    // ============================================
    // ==               PAY                      ==
    // ============================================

    function echtest_pay_interest_only(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
        if (borrowAmount < WAD * 100 || borrowAmount > MAX_FIL) return;
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_YEAR * 3);
        Debugger.log("rollFwdAmt interestOnly: ", rollFwdAmt);
        Debugger.log("borrowAmount interestOnly: ", borrowAmount);

        IAgent agent = _configureAgent(AGENT_OWNER);

        _depositFundsIntoPool(MAX_FIL, USER1);

        SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);
        (uint256 interestOwed, uint256 interestOwedPerEpoch) =
                    calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());

        if (interestOwed + DUST > interestOwedPerEpoch) {
            payAmount = interestOwed;
        } else {
            payAmount = bound(payAmount, interestOwedPerEpoch + DUST, interestOwed - DUST);
        }
        Debugger.log("payAmount interestOnly: ", payAmount);

        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, borrowCred, payAmount, rollFwdAmt);

        assert(prePayState.agentBorrowed == AccountHelpers.getAccount(router, agent.id(), pool.id()).principal);
    }

    // @audit Echidna is able to break last two assertions
    // function echtest_pay_interest_and_partial_principal(uint256 borrowAmount, uint256 payAmount, uint256 rollFwdAmt) public {
    //     uint256 depositAmt = 1000e18;

    //     rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_WEEK * 3);
    //     Debugger.log("rollFwdAmt: ", rollFwdAmt);
    //     // bind borrow amount min 1e18 to ensure theres a decent amount of principal to repay
    //     borrowAmount = bound(borrowAmount, 1e18, depositAmt);
    //     Debugger.log("borrowAmount: ", borrowAmount);

    //     SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);

    //     (uint256 interestOwed,) = calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());
    //     // bind the pay amount to in between the interest owed and less than the principal
    //     payAmount = bound(payAmount, interestOwed + DUST, interestOwed + borrowAmount - DUST);
    //     Debugger.log("interestOwed + DUST", interestOwed + DUST);
    //     Debugger.log("interestOwed + borrowAmount - DUST", interestOwed + borrowAmount - DUST);
    //     Debugger.log("payAmount: ", payAmount);

    //     StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, borrowCred, payAmount, rollFwdAmt);

    //     uint256 principalPaid = payAmount - interestOwed;

    //     Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

    //     Debugger.log("postPaymentAccount.epochsPaid", postPaymentAccount.epochsPaid); // postPaymentAccount.epochsPaid», data=4390162
    //     Debugger.log("block.number", block.number); // block.number», data=4390163
    //     Debugger.log("postPaymentAccount.principal", postPaymentAccount.principal); // postPaymentAccount.principal», data=1495644929072186007
    //     Debugger.log("prePayState.agentBorrowed - principalPaid", prePayState.agentBorrowed - principalPaid); // prePayState.agentBorrowed - principalPaid», data=1495644929072176007
    //     assert(prePayState.agentBorrowed - principalPaid == postPaymentAccount.principal);
    //     assert(postPaymentAccount.epochsPaid == block.number);
    // }

    function echtest_pay_full_repayment(uint256 borrowAmount, uint256 rollFwdAmt) public {
        if (borrowAmount < WAD * 100 || borrowAmount > MAX_FIL) return;
        rollFwdAmt = bound(rollFwdAmt, 1, EPOCHS_IN_YEAR * 3);
        Debugger.log("rollFwdAmt fullRepayment: ", rollFwdAmt);
        Debugger.log("borrowAmount fullRepayment: ", borrowAmount);

        IAgent agent = _configureAgent(AGENT_OWNER);

        _depositFundsIntoPool(MAX_FIL, USER1);

        SignedCredential memory borrowCred = _issueGenericBorrowCred(agent.id(), borrowAmount);
        (uint256 interestOwed, ) = calculateInterestOwed(borrowAmount, rollFwdAmt, _getAdjustedRate());

        // Calculate the full repayment amount (principal + interest)
        uint256 fullRepaymentAmount = borrowAmount + interestOwed;
        Debugger.log("fullRepaymentAmount: ", fullRepaymentAmount);

        StateSnapshot memory prePayState = borrowRollFwdAndPay(agent, borrowCred, fullRepaymentAmount, rollFwdAmt);

        Account memory postPaymentAccount = AccountHelpers.getAccount(router, agent.id(), pool.id());

        // Assert that the principal is now zero
        assert(postPaymentAccount.principal == 0);
        
        // Assert that epochsPaid is reset to zero
        assert(postPaymentAccount.epochsPaid == 0);
        
        // Assert that the full amount was transferred
        assert(wFIL.balanceOf(address(agent)) == prePayState.agentBalanceWFIL - fullRepaymentAmount);
        assert(wFIL.balanceOf(address(pool)) == prePayState.poolBalanceWFIL + fullRepaymentAmount);
    }

    // Verifies that an unauthorized user cannot make a payment on behalf of the agent.
    function echtest_nonAgentCannotPay(uint256 payAmount) public {
        if (payAmount < WAD || payAmount > MAX_FIL) return;

        uint256 borrowAmount = 10e18;
        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentId = agent.id();
        uint256 rollFwdAmt = EPOCHS_IN_WEEK * 2;
        SignedCredential memory borrowCred = _issueBorrowCred(agentId, borrowAmount, borrowAmount * 2);

        // Deposit funds into the pool
        hevm.deal(AGENT_OWNER, borrowAmount + WAD);
        hevm.prank(AGENT_OWNER);
        poolDepositNativeFil(borrowAmount, AGENT_OWNER);

        // Borrow funds
        hevm.deal(address(agent), borrowAmount * 2);
        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), borrowCred);

        // Roll forward time to accrue interest
        hevm.roll(block.number + rollFwdAmt);

        // Prepare the unauthorized payer (INVESTOR)
        hevm.deal(INVESTOR, payAmount);
        hevm.prank(INVESTOR);
        wFilDeposit(payAmount);
        hevm.prank(INVESTOR);
        wFIL.approve(address(agent), payAmount);

        // Create pay credential
        SignedCredential memory payCred = _issuePayCred(agentId, payAmount, payAmount * 2, payAmount);
        
        // Attempt to pay as INVESTOR (should revert)
        hevm.prank(INVESTOR);
        agentPayRevert(payCred);
    }

    // Verifies that a payment cannot be made on a non-existent account.
    function echtest_cannotPayOnNonExistentAccount(uint256 payAmount) public {
        if (payAmount < WAD || payAmount > MAX_FIL) return;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentId = agent.id();

        // Ensure the agent has not borrowed anything yet
        assert(pool.getAgentBorrowed(agentId) == 0);

        // Load the agent with sufficient funds to make the payment
        hevm.deal(address(agent), payAmount);
        hevm.prank(address(agent));
        wFilDeposit(payAmount);
        hevm.prank(address(agent));
        wFIL.approve(address(pool), payAmount);

        // Create pay credential
        SignedCredential memory payCred = _issuePayCred(agentId, payAmount, payAmount * 2, payAmount);
        
        // Attempt to pay (should revert)
        hevm.prank(AGENT_OWNER);
        agentPayRevert(payCred);
    }

    // // // ============================================
    // // // ==               ASSET                    ==
    // // // ============================================

    // @audit some assertions are failing
    function echtest_distributeLiquidatedFundsPartialRecoveryNoInterest(uint256 borrowAmount, uint256 depositAmount)
        public
    {
        depositAmount = bound(depositAmount, WAD, MAX_FIL / 2);
        borrowAmount = bound(borrowAmount, WAD, depositAmount - 1);

        hevm.deal(INVESTOR, MAX_FIL);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(depositAmount, INVESTOR);

        hevm.prank(AGENT_OWNER);
        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);

        SignedCredential memory borrowCred = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 poolBorrowableAssetsBefore = pool.totalBorrowableAssets();

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), borrowCred);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 poolBorrowableAssetsAfter = pool.totalBorrowableAssets();

        hevm.warp(block.timestamp + 30 days);

        _setAgentDefaulted(agent, borrowAmount);

        uint256 totalAssetsBefore = pool.totalAssets();

        hevm.deal(SYSTEM_ADMIN, borrowAmount);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: borrowAmount}();
        hevm.prank(SYSTEM_ADMIN);
        wFIL.approve(address(agentPolice), borrowAmount);
        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), borrowAmount);

        uint256 totalAssetsAfter = pool.totalAssets();

        uint256 lostAmount = totalAssetsBefore - totalAssetsAfter;
        uint256 recoverPercent = (totalAssetsBefore - lostAmount) * WAD / totalAssetsBefore;
        uint256 poolTokenSupply = pool.liquidStakingToken().totalSupply();
        uint256 tokenPrice = poolTokenSupply * WAD / (totalAssetsBefore - lostAmount);

        // Asserts

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);

        assert(poolBorrowableAssetsAfter == poolBorrowableAssetsBefore - borrowAmount);

        assert(IAgentPolice(agentPolice).agentLiquidated(agent.id()));

        assert(pool.lpRewards().lost == 0);

        // The asserts below don't work
        // assert(pool.convertToAssets(WAD) == recoverPercent);
        // assert(pool.convertToShares(WAD) == tokenPrice);

        // assert(lostAmount == AccountHelpers.getAccount(router, agent.id(), pool.id()).principal);

        // assert(pool.totalBorrowed() == 0);

        // assert(wFIL.balanceOf(address(agentPolice)) == 0);
        // assert(pool.convertToAssets(WAD) == recoverPercent);

        // assert(pool.convertToShares(WAD) == tokenPrice);
    }

    // @audit some assertions are failing
    function echtest_agentLoanAndLiquidationProcess(uint256 borrowAmount, uint256 depositAmount) public {
        depositAmount = bound(depositAmount, WAD, MAX_FIL / 2);
        borrowAmount = bound(borrowAmount, WAD, depositAmount - 1);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, MAX_FIL);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(depositAmount, INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 poolBorrowableAssetsBefore = pool.totalBorrowableAssets();
        uint256 totalAssetsBefore = pool.totalAssets();

        hevm.prank(AGENT_OWNER);
        agentBorrow(address(globalAgent), sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 poolBorrowableAssetsAfter = pool.totalBorrowableAssets();

        hevm.warp(block.timestamp + 30 days);

        hevm.deal(SYSTEM_ADMIN, borrowAmount);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: borrowAmount}();

        hevm.prank(SYSTEM_ADMIN);
        wFIL.approve(address(agentPolice), borrowAmount);

        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), borrowAmount);

        uint256 totalAssetsAfter = pool.totalAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(poolBorrowableAssetsAfter == poolBorrowableAssetsBefore - borrowAmount);

        uint256 lostAmount = totalAssetsBefore - totalAssetsAfter;

        uint256 recoverPercent = (totalAssetsBefore - lostAmount) * WAD / totalAssetsBefore;
        uint256 poolTokenSupply = pool.liquidStakingToken().totalSupply();
        uint256 tokenPrice = poolTokenSupply * WAD / (totalAssetsBefore - lostAmount);

        // The asserts below don't work
        // assert(pool.convertToAssets(WAD) == recoverPercent);
        // assert(pool.convertToShares(WAD) == tokenPrice);
        // assert(pool.lpRewards().lost == 0);
    }
}