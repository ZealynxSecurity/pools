// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";

contract EchidnaAgent is EchidnaSetup {
    constructor() payable {}

    // ============================================
    // ==               BORROW                   ==
    // ============================================

    function echtest_agent_borrow() public {
        // borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        uint256 borrowAmount = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        // ensure theres enough to deposit
        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        // 2x liquidation value will always pass
        uint256 liquidationValue = borrowAmount * 2;
        // fund the agent with its liquidation value to pass the check
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        // @audit this fails, not sure why
        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
    }

    function echtest_credential_actions() public {
        uint256 agentID = 1;
        uint64 minerID = 1;

        SignedCredential memory sc = _issueAddMinerCred(agentID, minerID);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.addMiner.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 principal = 10e18;
        uint256 liquidationValue = 5e18;
        sc = _issueBorrowCred(agentID, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.borrow.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 paymentAmount = 1e18;
        sc = _issuePayCred(agentID, principal, liquidationValue, paymentAmount);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.pay.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        sc = _issueRemoveMinerCred(agentID, minerID, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.removeMiner.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 amount = 5e18;
        sc = _issueWithdrawCred(agentID, amount, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.withdraw.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }
    }

    function echtest_agent_borrow_fuzz(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 1, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 poolBorrowableAssetsBefore = pool.totalBorrowableAssets();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 poolBorrowableAssetsAfter = pool.totalBorrowableAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(poolBorrowableAssetsAfter == poolBorrowableAssetsBefore - borrowAmount);
    }

    // function test_agent_borrow_balance(uint256 borrowAmount) public {
    //     borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

    //     IAgent agent = _configureAgent(AGENT_OWNER);
    //     uint256 agentID = agent.id();

    //     hevm.deal(INVESTOR, borrowAmount + WAD);
    //     hevm.prank(INVESTOR);
    //     pool.deposit{value: borrowAmount}(INVESTOR);

    //     uint256 liquidationValue = borrowAmount * 2;
    //     hevm.deal(address(agent), liquidationValue);
    //     SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

    //     uint256 agentBalanceBefore = address(agent).balance;
    //     uint256 poolBalanceBefore = address(pool).balance;

    //     hevm.prank(AGENT_OWNER);
    //     agent.borrow(poolID, sc);

    //     uint256 agentBalanceAfter = address(agent).balance;
    //     uint256 poolBalanceAfter = address(pool).balance;

    //     assert(agentBalanceAfter == agentBalanceBefore + borrowAmount);
    //     assert(poolBalanceAfter == poolBalanceBefore - borrowAmount);
    // }

    function echtest_agent_borrow_min(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 1, WAD);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
    }

    function echtest_agent_borrow_large(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, MAX_FIL / 2, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
    }

    function echtest_agent_borrow_small(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 1, WAD / 2);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
    }

    // function test_agent_borrow_insufficient_liquidity(uint256 borrowAmount) public {
    //     borrowAmount = bound(borrowAmount, MAX_FIL + 1, MAX_FIL * 2);
    //     Debugger.log("Borrow Amount", borrowAmount);

    //     IAgent agent = _configureAgent(AGENT_OWNER);
    //     uint256 agentID = agent.id();
    //     Debugger.log("Agent ID", agentID);

    //     hevm.deal(INVESTOR, MAX_FIL);
    //     hevm.prank(INVESTOR);
    //     pool.deposit{value: MAX_FIL}(INVESTOR);
    //     Debugger.log("Investor Balance After Deposit", INVESTOR.balance);

    //     uint256 liquidationValue = borrowAmount * 2;
    //     hevm.deal(address(agent), liquidationValue);
    //     Debugger.log("Agent Balance After Liquidation Deal", address(agent).balance);

    //     SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

    //     Debugger.log("SignedCredential vc.subject", sc.vc.subject);
    //     Debugger.log("SignedCredential vc.value", sc.vc.value);
    //     Debugger.log("SignedCredential vc.target", sc.vc.target);
    //     Debugger.log("SignedCredential vc.issuer", uint256(uint160(sc.vc.issuer)));
    //     Debugger.log("SignedCredential v", sc.v);
    //     Debugger.log("SignedCredential r", uint256(sc.r));
    //     Debugger.log("SignedCredential s", uint256(sc.s));

    //     uint256 agentLiquidAssetsBefore = agent.liquidAssets();
    //     Debugger.log("Agent Liquid Assets Before", agentLiquidAssetsBefore);

    //     bool revertExpected = false;

    //     hevm.prank(AGENT_OWNER);
    //     try agent.borrow(poolID, sc) {
    //         revertExpected = true;
    //     } catch {
    //         revertExpected = false;
    //     }

    //     Debugger.log("Revert Expected", revertExpected);

    //     uint256 agentLiquidAssetsAfter = agent.liquidAssets();
    //     Debugger.log("Agent Liquid Assets After", agentLiquidAssetsAfter);

    //     assert(!revertExpected);
    //     assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    // }

    function echtest_agent_borrow_invalid_params(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, 0, WAD - 1);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        hevm.prank(AGENT_OWNER);
        try agent.borrow(poolID, sc) {
            assert(false);
        } catch {}

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    }

    function echtest_agent_borrow_not_owner(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        try agent.borrow(poolID, sc) {
            assert(false);
        } catch {}

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    }

    function echtest_agent_borrow_expired_credential() public {
        uint256 borrowAmount = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);

        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);
        sc.vc.epochValidUntil = block.number - 1;

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        bool revertExpected = false;

        hevm.prank(AGENT_OWNER);
        try agent.borrow(poolID, sc) {
            revertExpected = false;
        } catch {
            revertExpected = true;
        }

        Debugger.log("Revert Expected", revertExpected);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        Debugger.log("Agent Liquid Assets After", agentLiquidAssetsAfter);

        assert(revertExpected);
        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    }

    function echtest_agent_borrow_invalid_signature() public {
        uint256 borrowAmount = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);

        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);
        sc.s = bytes32(0);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        bool revertExpected = false;

        hevm.prank(AGENT_OWNER);
        try agent.borrow(poolID, sc) {
            revertExpected = false;
        } catch {
            revertExpected = true;
        }

        Debugger.log("Revert Expected", revertExpected);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        Debugger.log("Agent Liquid Assets After", agentLiquidAssetsAfter);

        assert(revertExpected);
        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore);
    }

    function echtest_agent_borrow_update_epochs_paid(uint256 borrowAmount, uint256 existingPrincipal) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        existingPrincipal = bound(existingPrincipal, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + existingPrincipal + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount + existingPrincipal}(INVESTOR);

        uint256 liquidationValue = (borrowAmount + existingPrincipal) * 2;
        hevm.deal(address(agent), liquidationValue);

        SignedCredential memory scInitial = _issueBorrowCred(agentID, existingPrincipal, liquidationValue);
        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scInitial);

        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 totalBorrowedAfter = pool.totalBorrowed();

        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);
        assert(totalBorrowedAfter == totalBorrowedBefore + borrowAmount);
    }

    function echtest_agent_borrow_rewards(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        (uint256 lpAccruedBefore, uint256 lpPaidBefore, uint256 lpLostBefore) = pool.getLpRewardsValues();
        (uint256 treasuryAccruedBefore, uint256 treasuryPaidBefore, uint256 treasuryLostBefore) =
            pool.getTreasuryRewardsValues();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        (uint256 lpAccruedAfter, uint256 lpPaidAfter, uint256 lpLostAfter) = pool.getLpRewardsValues();
        (uint256 treasuryAccruedAfter, uint256 treasuryPaidAfter, uint256 treasuryLostAfter) =
            pool.getTreasuryRewardsValues();

        // Verificar que las recompensas LP se acumularon
        assert(lpAccruedAfter >= lpAccruedBefore);
        assert(lpPaidAfter == lpPaidBefore);
        assert(lpLostAfter == lpLostBefore);

        // Verificar que las recompensas del Tesoro se acumularon
        assert(treasuryAccruedAfter >= treasuryAccruedBefore);
        assert(treasuryPaidAfter == treasuryPaidBefore);
        assert(treasuryLostAfter == treasuryLostBefore);
    }

    function echtest_agent_borrow_update_accounting(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();
        uint256 lastAccountingUpdateEpochBefore = pool.lastAccountingUpdateEpoch();

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        uint256 agentLiquidAssetsAfter = agent.liquidAssets();
        uint256 lastAccountingUpdateEpochAfter = pool.lastAccountingUpdateEpoch();
        uint256 currentBlockNumber = block.number;

        // Verify that the agent's liquid assets increased by the borrowed amount
        assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + borrowAmount);

        // Verify that the accounting was updated if block number has increased
        if (currentBlockNumber > lastAccountingUpdateEpochBefore) {
            assert(lastAccountingUpdateEpochAfter == currentBlockNumber);
        } else {
            assert(lastAccountingUpdateEpochAfter == lastAccountingUpdateEpochBefore);
        }
    }

    // // ============================================
    // // ==            BORROW - PAUSE              ==
    // // ============================================

    function echtest_agent_borrow_paused(uint256 borrowAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        // Pause the pool
        hevm.prank(AGENT_OWNER);
        pool.pause();

        // Try to borrow and expect a revert due to the pool being paused
        hevm.prank(AGENT_OWNER);
        try agent.borrow(poolID, sc) {
            assert(false); // Should not reach here as the pool is paused
        } catch {
            // Expected revert due to the pool being paused
        }

        // Verify that the pool is paused
        assert(pool.paused());
    }

    // ============================================
    // ==               PAY                      ==
    // ============================================

    // Verifies that an unauthorized user cannot make a payment on behalf of the agent.
    function echtest_nonAgentCannotPay(uint256 payAmount) public {
        payAmount = bound(payAmount, WAD, MAX_FIL);
        uint256 borrowAmount = 10e18;
        uint256 poolId = pool.id();
        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentId = agent.id();
        uint256 rollFwdAmt = EPOCHS_IN_WEEK * 2;
        SignedCredential memory borrowCred = _issueBorrowCred(agentId, borrowAmount, borrowAmount * 2);

        hevm.deal(AGENT_OWNER, borrowAmount + WAD);
        hevm.prank(AGENT_OWNER);
        pool.deposit{value: borrowAmount}(AGENT_OWNER);

        hevm.deal(address(agent), borrowAmount * 2);
        hevm.prank(AGENT_OWNER);
        agent.borrow(poolId, borrowCred);

        hevm.roll(block.number + rollFwdAmt);

        // Load the payer with sufficient funds to make the payment
        hevm.deal(INVESTOR, payAmount);
        hevm.prank(INVESTOR);
        wFIL.deposit{value: payAmount}();

        wFIL.approve(address(pool), payAmount);

        SignedCredential memory payCred = _issuePayCred(agentId, payAmount, payAmount * 2, payAmount);
        bool success;
        hevm.prank(INVESTOR);
        try agent.pay(poolId, payCred) {
            success = true;
        } catch {
            success = false;
        }
        assert(!success); // Expected revert due to unauthorized payer
    }

    // Verifies that a payment cannot be made on a non-existent account.
    function echtest_cannotPayOnNonExistentAccount(uint256 payAmount) public {
        payAmount = bound(payAmount, WAD, MAX_FIL);
        uint256 poolId = pool.id();
        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentId = agent.id();

        // Load the payer with sufficient funds to make the payment
        hevm.deal(address(agent), payAmount);
        hevm.prank(address(agent));
        wFIL.deposit{value: payAmount}();
        wFIL.approve(address(pool), payAmount);

        SignedCredential memory payCred = _issuePayCred(agentId, payAmount, payAmount * 2, payAmount);
        bool success;
        hevm.prank(AGENT_OWNER);
        try agent.pay(poolId, payCred) {
            success = true;
        } catch {
            success = false;
        }
        assert(!success); // Expected revert due to non-existent account
    }

    // Verifies that a full debt payment updates the account values correctly and returns the appropriate refund.
    function echtest_payFullDebt(uint256 borrowAmount, uint256 repayAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        repayAmount = bound(repayAmount, borrowAmount, borrowAmount * 2);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        SignedCredential memory scRepay = _issuePayCred(agentID, repayAmount, liquidationValue, repayAmount);

        hevm.prank(AGENT_OWNER);
        (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund) = agent.pay(poolID, scRepay);

        Account memory account = pool.getAccount(agentID);

        assert(account.principal == 0); // Debt should be fully paid
        assert(principalPaid == borrowAmount); // Principal paid should match borrow amount
        assert(refund == repayAmount - borrowAmount); // Refund should be the difference between repay amount and borrow amount
    }

    // Verifies that a partial debt payment correctly reduces the account principal.
    function echtest_payPartialDebt(uint256 borrowAmount, uint256 repayAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        repayAmount = bound(repayAmount, WAD, borrowAmount - 1);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        SignedCredential memory scRepay = _issuePayCred(agentID, repayAmount, liquidationValue, repayAmount);

        hevm.prank(AGENT_OWNER);
        (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund) = agent.pay(poolID, scRepay);

        Account memory account = pool.getAccount(agentID);

        assert(account.principal == borrowAmount - repayAmount); // Principal should be reduced by the repay amount
        assert(principalPaid == repayAmount); // Principal paid should match repay amount
        assert(refund == 0); // No refund should be given
    }

    // Verifies that an excess payment correctly returns the refund amount to the agent.
    function echtest_excessPayment(uint256 borrowAmount, uint256 repayAmount) public {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        repayAmount = bound(repayAmount, borrowAmount + 1, borrowAmount * 2);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        SignedCredential memory scRepay = _issuePayCred(agentID, repayAmount, liquidationValue, repayAmount);

        hevm.prank(AGENT_OWNER);
        (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund) = agent.pay(poolID, scRepay);

        Account memory account = pool.getAccount(agentID);

        assert(account.principal == 0); // Debt should be fully paid
        assert(principalPaid == borrowAmount); // Principal paid should match borrow amount
        assert(refund == repayAmount - borrowAmount); // Refund should be the excess amount paid
    }

    // function echtest_pay_full_debt(uint256 repayAmount, uint256 initialPrincipal) public {
    //     repayAmount = bound(repayAmount, WAD, MAX_FIL);
    //     initialPrincipal = bound(initialPrincipal, WAD, MAX_FIL);

    //     IAgent agent = _configureAgent(AGENT_OWNER);
    //     uint256 agentID = agent.id();

    //     hevm.deal(INVESTOR, initialPrincipal + WAD);
    //     hevm.prank(INVESTOR);
    //     pool.deposit{value: initialPrincipal}(INVESTOR);

    //     uint256 liquidationValue = initialPrincipal * 2;
    //     hevm.deal(address(agent), liquidationValue);
    //     SignedCredential memory scBorrow = _issueBorrowCred(agentID, initialPrincipal, liquidationValue);

    //     hevm.prank(AGENT_OWNER);
    //     agent.borrow(poolID, scBorrow);

    //     uint256 agentLiquidAssetsBefore = agent.liquidAssets();

    //     // Repay the debt
    //     SignedCredential memory scRepay = _issuePayCred(agentID, initialPrincipal, liquidationValue, repayAmount);
    //     hevm.prank(AGENT_OWNER);
    //     (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund) = agent.pay(poolID, scRepay);

    //     uint256 agentLiquidAssetsAfter = agent.liquidAssets();

    //     // Verify that the agent's liquid assets increased by the refund amount
    //     assert(agentLiquidAssetsAfter == agentLiquidAssetsBefore + refund);
    //     // Verify that the total borrowed amount decreased by the principal paid
    //     assert(pool.totalBorrowed() == initialPrincipal - principalPaid);
    // }
}
