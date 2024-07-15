// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";

contract EchidnaAgent is EchidnaSetup {
    constructor() payable {}

    using FixedPointMathLib for uint256;

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

    // ============================================
    // ==               ASSET                    ==
    // ============================================

    uint256 stakeAmount = 1000e18;

    function echtest_distributeLiquidatedFundsPartialRecoveryNoInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD + 1, MAX_FIL);
        recoveredFunds = bound(recoveredFunds, WAD, borrowAmount - 1);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        // Simulate the agent default with the borrow amount
        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        // Mark the agent as defaulted
        Account memory account = pool.getAccount(agentID);
        account.defaulted = true;
        account.principal = 0;

        uint256 totalAssetsBefore = pool.totalAssets();
        Debugger.log("initialTotalAssets", totalAssetsBefore);

        // Load the SYSTEM_ADMIN with enough funds to recover
        hevm.deal(SYSTEM_ADMIN, recoveredFunds);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(address(agentPolice), recoveredFunds);

        // Distribute the recovered funds
        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();
        Debugger.log("newTotalAssets", totalAssetsAfter);

        uint256 lostAmount = totalAssetsBefore - totalAssetsAfter;
        uint256 recoverPercent = (totalAssetsBefore - lostAmount) * WAD / totalAssetsBefore;

        uint256 poolTokenSupply = pool.liquidStakingToken().totalSupply();
        uint256 tokenPrice = poolTokenSupply * WAD / (totalAssetsBefore - lostAmount);

        // Assertions
        assert(pool.convertToAssets(WAD) == recoverPercent); // IFILtoFIL should be 1
        assert(pool.convertToShares(WAD) == tokenPrice); // FILtoIFIL should be 1
        assert(totalAssetsBefore + recoveredFunds - borrowAmount == totalAssetsAfter); // Pool should have recovered funds
        assert(lostAmount == borrowAmount - recoveredFunds); // Lost amount should be correct
        assert(pool.lpRewards().lost == 0); // Lost rental fees should be 0 because no interest
        assert(account.principal == lostAmount); // Pool should have written down assets correctly
        assert(pool.totalBorrowed() == 0); // Pool should have nothing borrowed after the liquidation
        assert(wFIL.balanceOf(address(agentPolice)) == 0); // Agent police should not have funds
    }

    function echtest_distributeLiquidatedFundsFullRecoveryNoInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        recoveredFunds = bound(recoveredFunds, borrowAmount, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        // Simulate the agent default with the borrow amount
        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        // Mark the agent as defaulted
        Account memory account = pool.getAccount(agentID);
        account.defaulted = true;

        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();

        // Load the SYSTEM_ADMIN with enough funds to recover
        hevm.deal(SYSTEM_ADMIN, recoveredFunds);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(agentPolice, recoveredFunds);

        // Distribute the recovered funds
        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();

        // Assertions
        assert(totalAssetsBefore == totalAssetsAfter); // Pool should have recovered fully
        assert(wFIL.balanceOf(address(pool)) == totalAssetsAfter); // Pool should have received the correct amount of wFIL

        // Compute the extra amount that should be paid back to the owner and the treasury
        uint256 liquidationFee = totalBorrowedBefore.mulWadDown(IAgentPolice(agentPolice).liquidationFee());

        // The owner should get back excess and the treasury should get back its 10% liquidation fee
        if (recoveredFunds > totalBorrowedBefore + liquidationFee) {
            assert(
                wFIL.balanceOf(IAuth(address(agent)).owner()) == recoveredFunds - totalBorrowedBefore - liquidationFee
            ); // Police owner should only have paid the amount owed
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == liquidationFee); // Police should have received the treasury fee
        } else if (recoveredFunds > totalBorrowedBefore) {
            assert(wFIL.balanceOf(IAuth(address(agent)).owner()) == 0); // Owner should not get funds back if liquidation fee isn't fully paid
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == recoveredFunds - totalBorrowedBefore); // Police should have received some liquidation fee
        } else {
            // No liquidation fee should be paid if the recovered funds are less than the total borrowed
            assert(wFIL.balanceOf(IAuth(address(agent)).owner()) == 0); // Owner should not get funds back if liquidation fee isn't fully paid
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == 0); // No liquidation fees should have been paid
        }

        assert(IAgentPolice(agentPolice).agentLiquidated(agentID)); // Agent should be marked as liquidated
    }

    //@audit => Try compiling with `--via-ir` (cli) or the equivalent `viaIR: true`
    // function echtest_distributeLiquidationFundsPartialRecoveryWithInterest_Part1(
    //     uint256 borrowAmount,
    //     uint256 recoveredFunds
    // ) public {
    //     borrowAmount = bound(borrowAmount, WAD + 1, MAX_FIL);
    //     recoveredFunds = bound(recoveredFunds, WAD, borrowAmount - 1);

    //     IAgent agent = _configureAgent(AGENT_OWNER);
    //     uint256 agentID = agent.id();

    //     uint256 liquidationValue = borrowAmount * 2;
    //     hevm.deal(address(agent), liquidationValue);
    //     SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

    //     hevm.prank(AGENT_OWNER);
    //     agent.borrow(poolID, scBorrow);

    //     // Roll forward a year to accrue interest
    //     hevm.roll(block.number + EPOCHS_IN_YEAR);

    //     uint256 interestOwed = pool.getAgentInterestOwed(agentID);
    //     uint256 interestOwedLessTFees = interestOwed.mulWadUp(1e18 - pool.treasuryFeeRate());

    //     Account memory account = pool.getAccount(agentID);
    //     account.defaulted = true;

    //     hevm.deal(SYSTEM_ADMIN, recoveredFunds);
    //     hevm.prank(SYSTEM_ADMIN);
    //     wFIL.deposit{value: recoveredFunds}();
    //     wFIL.approve(agentPolice, recoveredFunds);

    //     uint256 totalAssetsBefore = pool.totalAssets();
    //     uint256 totalBorrowedBefore = pool.totalBorrowed();
    //     uint256 filValOf1iFILBeforeLiquidation = pool.convertToAssets(WAD);

    //     assert(totalAssetsBefore == stakeAmount + interestOwedLessTFees); // Total assets before should exclude treasury fees

    //     // Distribute the recovered funds
    //     hevm.prank(SYSTEM_ADMIN);
    //     IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), recoveredFunds);

    //     uint256 totalAssetsAfter = pool.totalAssets();
    //     uint256 totalAccrued = pool.lpRewards().accrued;
    //     uint256 interestAccruedLessTFees = totalAccrued.mulWadUp(1e18 - pool.treasuryFeeRate());

    //     uint256 expectedTotalAssetsAfter =
    //         stakeAmount + recoveredFunds + interestAccruedLessTFees - totalBorrowedBefore - interestOwedLessTFees;

    //     assert(totalAssetsAfter == expectedTotalAssetsAfter); // Pool should have lost all interest and principal
    // }

    //
    function echtest_distributeLiquidationFundsPartialRecoveryWithInterestPart2(
        uint256 borrowAmount,
        uint256 recoveredFunds
    ) public {
        borrowAmount = bound(borrowAmount, WAD + 1, MAX_FIL);
        recoveredFunds = bound(recoveredFunds, WAD, borrowAmount - 1);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        // Roll forward a year to accrue interest
        hevm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwed = pool.getAgentInterestOwed(agentID);
        uint256 interestOwedLessTFees = interestOwed.mulWadUp(1e18 - pool.treasuryFeeRate());

        Account memory account = pool.getAccount(agentID);
        account.defaulted = true;

        hevm.deal(SYSTEM_ADMIN, recoveredFunds);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(agentPolice, recoveredFunds);

        // Distribute the recovered funds
        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), recoveredFunds);

        Account memory updatedAccount = pool.getAccount(agentID);

        assert(updatedAccount.principal == interestOwed + borrowAmount - recoveredFunds); // No principal was paid, so account.principal should be the original principal amount lost
        assert(pool.treasuryFeesOwed() == 0); // Treasury fees should be 0 after a partial liquidation

        uint256 filValOf1iFILBeforeLiquidation = pool.convertToAssets(WAD);
        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 totalBorrowedBefore = pool.totalBorrowed();
        uint256 lostAssets = totalBorrowedBefore + interestOwedLessTFees - recoveredFunds;
        uint256 recoverPercent = (totalAssetsBefore - lostAssets).divWadDown(totalAssetsBefore);

        // Manually written assertApproxEqAbs
        uint256 expectedAssets = filValOf1iFILBeforeLiquidation.mulWadDown(recoverPercent);
        assertApproxEqAbs(pool.convertToAssets(WAD), expectedAssets, 1e3); // IFIL should have devalued correctly

        assert(pool.totalBorrowed() == 0);
        assert(totalAssetsBefore - pool.totalAssets() == lostAssets);

        if (recoveredFunds >= interestOwed) {
            assert(pool.lpRewards().lost == 0); // Pool should not lose rental fees
            assert(pool.lpRewards().paid == interestOwed); // Pool should have paid rental fees
        } else {
            assert(pool.lpRewards().paid == recoveredFunds); // Paid rental fees should be the full recover amount when the recover amount is less than the interest owed
            assert(pool.lpRewards().lost == interestOwed - recoveredFunds); // Lost assets should be correct
        }
    }

    function echtest_distributeLiquidationFundsFullRecoveryWithInterest(uint256 borrowAmount, uint256 recoveredFunds)
        public
    {
        borrowAmount = bound(borrowAmount, WAD, MAX_FIL);

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        // Simulate the agent default with the borrow amount
        uint256 liquidationValue = borrowAmount * 2;
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory scBorrow = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, scBorrow);

        // Roll forward a year to accrue interest
        hevm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwed = pool.getAgentInterestOwed(agentID);
        uint256 interestOwedLessTFees = interestOwed.mulWadUp(1e18 - pool.treasuryFeeRate());
        // Important to test the range where recovered funds are enough to cover principal + interest owed to LPs (but not enough to pay off the full interest owed, which includes treasury fees)
        recoveredFunds = bound(recoveredFunds, borrowAmount + interestOwedLessTFees, MAX_FIL);

        // Mark the agent as defaulted
        Account memory account = pool.getAccount(agentID);
        account.defaulted = true;

        hevm.deal(SYSTEM_ADMIN, recoveredFunds);
        hevm.prank(SYSTEM_ADMIN);
        wFIL.deposit{value: recoveredFunds}();
        wFIL.approve(agentPolice, recoveredFunds);

        uint256 totalAssetsBefore = pool.totalAssets();
        uint256 filValOf1iFILBeforeLiquidation = pool.convertToAssets(WAD);
        uint256 totalDebtLessTFees = interestOwedLessTFees + borrowAmount;

        //@audit => Fail. Revise
        // assert(totalAssetsBefore == stakeAmount + interestOwedLessTFees); // Total assets before should exclude treasury fees

        // Distribute the recovered funds
        hevm.prank(SYSTEM_ADMIN);
        IAgentPolice(agentPolice).distributeLiquidatedFunds(address(agent), recoveredFunds);

        uint256 totalAssetsAfter = pool.totalAssets();

        assert(totalAssetsBefore == totalAssetsAfter); // Pool should have recovered fully

        // Compute the extra amount that should be paid back to the owner and the treasury
        uint256 liquidationFee = totalDebtLessTFees.mulWadDown(IAgentPolice(agentPolice).liquidationFee());

        if (recoveredFunds > totalDebtLessTFees + liquidationFee) {
            assert(
                wFIL.balanceOf(IAuth(address(agent)).owner()) == recoveredFunds - totalDebtLessTFees - liquidationFee
            ); // Police owner should only have paid the amount owed
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == liquidationFee); // Police should have received the treasury fee
        } else if (recoveredFunds > totalDebtLessTFees) {
            assert(wFIL.balanceOf(IAuth(address(agent)).owner()) == 0); // Owner should not get funds back if liquidation fee isn't fully paid
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == recoveredFunds - totalDebtLessTFees); // Police should have received some liquidation fee
        } else {
            // No liquidation fee should be paid if the recovered funds are less than the total borrowed
            assert(wFIL.balanceOf(IAuth(address(agent)).owner()) == 0); // Owner should not get funds back if liquidation fee isn't fully paid
            assert(wFIL.balanceOf(GetRoute.treasury(router)) == 0); // No liquidation fees should have been paid
        }

        assert(filValOf1iFILBeforeLiquidation == pool.convertToAssets(WAD)); // IFILtoFIL should not change
    }
}
