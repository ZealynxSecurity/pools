// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";

contract EchidnaInfinityPoolV2 is EchidnaSetup {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    constructor() payable {}

    // ============================================
    // ==               DEPOSIT                  ==
    // ============================================

    function echtest_deposit_wFIL(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        uint256 poolBalBefore = wFIL.balanceOf(address(pool));
        uint256 lstBalanceBefore = pool.liquidStakingToken().balanceOf(address(INVESTOR));
        uint256 predictedLST = pool.previewDeposit(stakeAmount);

        _loadApproveWFIL(stakeAmount, INVESTOR);
        hevm.prank(INVESTOR);
        poolDeposit(stakeAmount, INVESTOR);

        uint256 poolBalAfter = wFIL.balanceOf(address(pool));
        uint256 lstBalanceAfter = pool.liquidStakingToken().balanceOf(address(INVESTOR));
        
        assert(poolBalAfter == poolBalBefore + stakeAmount);
        assert(lstBalanceAfter == lstBalanceBefore + predictedLST);
    }

    function echtest_deposit_FIL(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        hevm.deal(INVESTOR, stakeAmount + WAD);

        uint256 investorIFILBalBefore = iFIL.balanceOf(INVESTOR);

        hevm.prank(INVESTOR);
        uint256 sharesDeposit = pool.deposit{value: stakeAmount}(INVESTOR);

        assert(sharesDeposit == stakeAmount);
        assert(sharesDeposit == iFIL.balanceOf(INVESTOR) - investorIFILBalBefore);
    }

    function echtest_wFILTotalSupplyInvariant(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is sufficiently funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(WAD, INVESTOR);

        hevm.prank(INVESTOR);
        wFilDeposit(stakeAmount);
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        // Check wFIL invariant
        assert(investorWFILBalStart + poolWFILBalStart == wFIL.totalSupply());
    }

    // Test that depositing zero amount reverts the transaction
    function echtest_zeroDepositReverts() public {
        uint256 zeroAmount = 0;

        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFilReverts(zeroAmount, INVESTOR);
    }

    // Test that attempting to deposit more than balance reverts the transaction
    function echtest_exceedingInvestorBalanceReverts() public {
        hevm.deal(INVESTOR, WAD);

        // Verify that depositing more than balance reverts
        hevm.prank(INVESTOR);
        poolDepositNativeFilReverts(WAD + 10, INVESTOR);
    }

    // Test to ensure correct shares are issued after a second deposit
    function echtest_correctSharesAfterSecondDeposit(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        hevm.deal(INVESTOR, MAX_FIL + WAD);

        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        hevm.prank(INVESTOR);
        uint256 sharesSecondDeposit = pool.deposit{value: stakeAmount}(INVESTOR);

        assert(sharesSecondDeposit == stakeAmount);
    }

    // Test to verify investor shares balance after multiple deposits
    function echtest_investorSharesBalanceAfterDeposits(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        
        hevm.deal(INVESTOR, MAX_FIL * 3);
        _loadApproveWFIL(stakeAmount, INVESTOR);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        hevm.prank(INVESTOR);
        poolDeposit(stakeAmount, INVESTOR);

        uint256 investorIFILBalEnd = iFIL.balanceOf(INVESTOR);

        assert(pool.convertToAssets(investorIFILBalEnd) == stakeAmount + investorIFILBalStart);
        assert(pool.convertToShares(stakeAmount) == investorIFILBalEnd - investorIFILBalStart);
    }

    // Test to verify preview deposit rounding error
    function echtest_previewDepositRoundingError(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(WAD, INVESTOR);

        // Perform a deposit to initialize the pool
        hevm.prank(INVESTOR);
        poolDepositNativeFil(1 ether, INVESTOR);

        // Get the total supply and total assets after the initial deposit
        uint256 totalSupply = pool.liquidStakingToken().totalSupply();
        uint256 totalAssets = pool.totalAssets();

        // Get the shares from previewDeposit for stakeAmount
        uint256 shares = pool.previewDeposit(stakeAmount);

        // Calculate expected shares using the same logic as in convertToShares
        uint256 expectedShares = totalSupply == 0 ? stakeAmount : stakeAmount.mulDivDown(totalSupply, totalAssets);

        // Ensure that the shares are correctly calculated
        assert(shares == expectedShares);

        // Additional check: Ensure that shares are not zero
        assert(shares > 0);
    }

    // Test to verify token minting on deposit
    function echtest_tokenMintingOnDeposit(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(WAD, INVESTOR);

        hevm.prank(INVESTOR);
        wFilDeposit(stakeAmount);
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        // Track token balance before deposit
        uint256 tokenBalanceBefore = iFIL.balanceOf(INVESTOR);

        hevm.prank(INVESTOR);
        poolDeposit(stakeAmount, INVESTOR);

        // Assert token minting
        assert(iFIL.balanceOf(INVESTOR) == tokenBalanceBefore + stakeAmount);
    }

    // Test to ensure deposit reverts when the contract is paused
    function echtest_depositRevertsWhenPaused(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        IPausable(address(pool)).pause();

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);

        // Verify that depositing while paused reverts
        hevm.prank(INVESTOR);
        poolDepositNativeFilReverts(stakeAmount, INVESTOR);

        // Needed to reset the state to not affect the rest of the tests
        IPausable(address(pool)).unpause();
    }

    // Test to ensure deposit reverts with an invalid receiver
    function echtest_depositRevertsWithInvalidReceiver(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);

        // Verify that depositing to an invalid receiver reverts
        hevm.prank(INVESTOR);
        poolDepositReverts(stakeAmount, address(0));
    }

    // Test for handling multiple consecutive deposits
    function echtest_multipleConsecutiveDeposits(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);

        // Track balance before deposits
        uint256 balanceBefore = pool.totalAssets();

        // Perform multiple consecutive deposits
        for (uint256 i; i < 5; i++) {
            hevm.prank(INVESTOR);
            poolDepositNativeFil(stakeAmount, INVESTOR);
        }

        // Assert total balance is correct
        assert(pool.totalAssets() == balanceBefore + (stakeAmount * 5));
    }

    // // ============================================
    // // ==               WITHDRAW                 ==
    // // ============================================

    // // Test to verify successful withdrawal of assets
    // function echtest_successfulWithdrawal(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);
    //     uint256 initialPoolBalance = wFIL.balanceOf(address(pool));

    //     // Withdraw assets
    //     uint256 withdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(withdrawAmount, INVESTOR, INVESTOR);

    //     // Assert balances after withdrawal
    //     assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - withdrawAmount);
    //     assert(wFIL.balanceOf(address(pool)) == initialPoolBalance + withdrawAmount);
    // }

    // // Test to verify withdrawal with insufficient liquidity reverts
    // function echtest_withdrawRevertsOnInsufficientLiquidity(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Attempt to withdraw more assets than available
    //     uint256 withdrawAmount = pool.totalAssets() + 1;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawReverts(withdrawAmount, INVESTOR, INVESTOR);
    // }

    // // Test to verify withdrawal updates accounting correctly
    // function echtest_withdrawUpdatesAccounting(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialTotalAssets = pool.totalAssets();

    //     // Withdraw assets
    //     uint256 withdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(withdrawAmount, INVESTOR, INVESTOR);

    //     // Assert total assets after withdrawal
    //     assert(pool.totalAssets() == initialTotalAssets - withdrawAmount);
    // }

    // // Test to verify withdrawal with invalid receiver reverts
    // function echtest_withdrawRevertsWithInvalidReceiver(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Attempt to withdraw to an invalid receiver
    //     hevm.prank(INVESTOR);
    //     poolWithdrawReverts(stakeAmount, address(0), INVESTOR);
    // }

    // // Test to verify partial withdrawal
    // //@audit =>  poolWithdrawN(firstWithdrawAmount, INVESTOR, INVESTOR);
    // function echtest_partialWithdrawal(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 2, MAX_FIL); // Ensure stakeAmount is at least 2 to allow partial withdrawal

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);

    //     // Withdraw first half of the assets
    //     uint256 firstWithdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(firstWithdrawAmount, INVESTOR, INVESTOR);

    //     uint256 investorBalanceAfterFirstWithdrawal = wFIL.balanceOf(INVESTOR);

    //     // Withdraw second half of the assets
    //     uint256 secondWithdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(secondWithdrawAmount, INVESTOR, INVESTOR);

    //     uint256 investorBalanceAfterSecondWithdrawal = wFIL.balanceOf(INVESTOR);

    //     // Calculate the total withdrawn amount
    //     uint256 totalWithdrawn = firstWithdrawAmount + secondWithdrawAmount;

    //     // Assert balances after each withdrawal
    //     assert(investorBalanceAfterFirstWithdrawal == initialInvestorBalance - firstWithdrawAmount);
    //     assert(investorBalanceAfterSecondWithdrawal == investorBalanceAfterFirstWithdrawal - secondWithdrawAmount);
    // }

    // // Test to verify complete withdrawal
    // //@audit => poolWithdrawN(stakeAmount, INVESTOR, INVESTOR);
    // function echtest_completeWithdrawal(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, WAD, MAX_FIL); // @audit WAD is the minimum to deposit

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR); // @audit why do we make all kind of deposits and not the only one that we need????

    //     uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);
    //     uint256 initialPoolBalance = wFIL.balanceOf(address(pool));

    //     // Withdraw with conversion
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(stakeAmount, INVESTOR, INVESTOR);

    //     // Assert balances after withdrawal with conversion
    //     assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - stakeAmount);
    //     assert(wFIL.balanceOf(address(pool)) == initialPoolBalance);
    // }

    // // Test to verify multiple consecutive withdrawals
    // //@audit =>  poolWithdrawN(stakeAmount, INVESTOR, INVESTOR);
    // function echtest_multipleConsecutiveWithdrawals(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL / 2); // Ensure enough for multiple withdrawals

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount * 2);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount * 2);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount * 2, INVESTOR);

    //     uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);

    //     // Withdraw first half
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(stakeAmount, INVESTOR, INVESTOR);

    //     // Withdraw second half
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(stakeAmount, INVESTOR, INVESTOR);

    //     // Assert balances after consecutive withdrawals
    //     assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - stakeAmount * 2);
    // }

    // // Test to verify withdrawal with different owner and receiver

    // function echtest_withdrawDifferentOwnerReceiver(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.deal(RECEIVER, MAX_FIL * 3); // Ensure receiver is funded for testing

    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialReceiverBalance = wFIL.balanceOf(RECEIVER);

    //     // Withdraw with different owner and receiver
    //     hevm.prank(INVESTOR);
    //     poolWithdrawN(stakeAmount, RECEIVER, INVESTOR);

    //     // Assert balances after withdrawal
    //     assert(wFIL.balanceOf(RECEIVER) == initialReceiverBalance + stakeAmount);
    // }

    // // Test to verify withdrawal when contract is paused
    // //@audit => poolDepositNativeFil(WAD, INVESTOR);
    // function echtest_withdrawRevertsWhenPaused(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Pause the contract
    //     hevm.prank(SYSTEM_ADMIN);
    //     pool.pause();

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Attempt to withdraw while paused
    //     hevm.prank(INVESTOR);
    //     poolWithdrawReverts(stakeAmount, INVESTOR, INVESTOR);
    // }

    // // Test to verify withdrawal with amount zero
    // // function echtest_withdrawZeroAmount() public {
    // //     //@audit => Can a user withdraw 0?
    // //     uint256 stakeAmount = 1; // Ensure there is at least some stake

    // //     // Ensure the investor is funded and has deposited
    // //     hevm.deal(INVESTOR, MAX_FIL * 3);
    // //     hevm.prank(INVESTOR);
    // //     pool.deposit{value: WAD}(INVESTOR);

    // //     hevm.prank(INVESTOR);
    // //     wFIL.deposit{value: stakeAmount}();
    // //     hevm.prank(INVESTOR);
    // //     wFIL.approve(address(pool), stakeAmount);
    // //     hevm.prank(INVESTOR);
    // //     pool.deposit(stakeAmount, INVESTOR);

    // //     // Attempt to withdraw zero amount
    // //     hevm.prank(INVESTOR);
    // //     (bool success,) =
    // //         address(pool).call(abi.encodeWithSignature("withdraw(uint256,address,address)", 0, INVESTOR, INVESTOR));
    // //     assert(!success);
    // // }

    // // ============================================
    // // ==               WITHDRAWF                 ==
    // // ============================================

    // // Test for partial withdrawals handling
    // //@audit => poolWithdrawF(firstWithdrawAmount, INVESTOR, INVESTOR);
    // function echtest_partialWithdrawals(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 2, MAX_FIL / 2); // Ensure stakeAmount is at least 2 to allow partial withdrawal

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialInvestorBalance = INVESTOR.balance;

    //     // Perform first partial withdrawal
    //     uint256 firstWithdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(firstWithdrawAmount, INVESTOR, INVESTOR);

    //     uint256 investorBalanceAfterFirstWithdrawal = INVESTOR.balance;

    //     // Perform second partial withdrawal
    //     uint256 secondWithdrawAmount = stakeAmount / 2;
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(secondWithdrawAmount, INVESTOR, INVESTOR);

    //     uint256 investorBalanceAfterSecondWithdrawal = INVESTOR.balance;

    //     // Calculate the total withdrawn amount
    //     uint256 totalWithdrawn = firstWithdrawAmount + secondWithdrawAmount;

    //     // Assert total balance is correct after each withdrawal
    //     assert(investorBalanceAfterFirstWithdrawal == initialInvestorBalance + firstWithdrawAmount);
    //     assert(investorBalanceAfterSecondWithdrawal == investorBalanceAfterFirstWithdrawal + secondWithdrawAmount);
    // }

    // // Test for withdrawal reverts when paused
    // //@audit => poolDepositNativeFil(WAD, INVESTOR);
    // function echtest_withdrawFRevertsWhenPaused(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Pause the contract
    //     hevm.prank(SYSTEM_ADMIN);
    //     pool.pause();

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Simulate and verify that withdrawing while paused reverts
    //     hevm.prank(INVESTOR);
    //     poolWithdrawFReverts(stakeAmount, INVESTOR, INVESTOR);
    // }

    // // Test for withdrawal reverts with invalid receiver
    // function echtest_withdrawFRevertsWithInvalidReceiver(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Simulate and verify that withdrawing to an invalid receiver reverts
    //     hevm.prank(INVESTOR);
    //     poolWithdrawFReverts(stakeAmount, address(0), INVESTOR);
    // }

    // // Test to ensure correct balance transfer after withdraw with conversion
    // //@audit => poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);
    // function echtest_withdrawFWithConversion(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);

    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 initialInvestorBalance = INVESTOR.balance;

    //     // Withdraw with conversion
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);

    //     uint256 investorBalanceAfterWithdrawal = INVESTOR.balance;

    //     // Assert balances after withdrawal with conversion
    //     assert(investorBalanceAfterWithdrawal == initialInvestorBalance + stakeAmount);
    // }

    // // Test to verify InsufficientLiquidity revert
    // //@audit => poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);
    // function echtest_insufficientLiquidityRevert(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     // Withdraw all liquidity first
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);

    //     // Try to withdraw again with insufficient liquidity
    //     hevm.prank(INVESTOR);
    //     poolWithdrawFReverts(stakeAmount, INVESTOR, INVESTOR);
    // }

    // // Test for correct asset transfer during exit
    // //@audit =>  poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);
    // function echtest_assetTransferOnExit(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, 1, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 contractBalanceBefore = wFIL.balanceOf(address(pool));
    //     uint256 investorBalanceBefore = INVESTOR.balance;

    //     // Withdraw with conversion
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(stakeAmount, INVESTOR, INVESTOR); // @audit fails in liquidStakingToken.transferFrom(owner, address(this), iFILToBurn);


    //     uint256 contractBalanceAfter = wFIL.balanceOf(address(pool));
    //     uint256 investorBalanceAfter = INVESTOR.balance;

    //     // Assert asset transfer is correct
    //     assert(contractBalanceAfter == contractBalanceBefore - stakeAmount);
    //     assert(investorBalanceAfter == investorBalanceBefore + stakeAmount);
    // }

    // // Test for large withdrawals handling
    // //@audit =>  stakeAmount = bound(stakeAmount, MAX_FIL / 2, MAX_FIL);
    // function echtest_largeWithdrawals(uint256 stakeAmount) public {
    //     stakeAmount = bound(stakeAmount, MAX_FIL / 2, MAX_FIL);

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     poolDepositNativeFil(WAD, INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFilDeposit(stakeAmount);
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     poolDeposit(stakeAmount, INVESTOR);

    //     uint256 contractBalanceBefore = wFIL.balanceOf(address(pool));
    //     uint256 investorBalanceBefore = INVESTOR.balance;

    //     // Withdraw with conversion
    //     hevm.prank(INVESTOR);
    //     poolWithdrawF(stakeAmount, INVESTOR, INVESTOR);

    //     uint256 contractBalanceAfter = wFIL.balanceOf(address(pool));
    //     uint256 investorBalanceAfter = INVESTOR.balance;

    //     // Assert asset transfer is correct
    //     assert(contractBalanceAfter == contractBalanceBefore - stakeAmount);
    //     assert(investorBalanceAfter == investorBalanceBefore + stakeAmount);
    // }
}
