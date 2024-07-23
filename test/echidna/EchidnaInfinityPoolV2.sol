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

        uint256 investorWFILBal = wFIL.balanceOf(INVESTOR);
        uint256 poolWFILBal = wFIL.balanceOf(address(pool));

        // Check wFIL invariant
        // We have added USER1 balance as well because it is used in another test and is needed for calculating the total supply
        assert(investorWFILBal + poolWFILBal + wFIL.balanceOf(USER1) == wFIL.totalSupply());
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

    // Test to verify successful withdrawal of assets
    function echtest_successfulWithdrawal(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 iFILSupply = iFIL.totalSupply();
        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);

        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        hevm.prank(INVESTOR);
        uint256 sharesBurned = pool.withdraw(withdrawAmount, INVESTOR, INVESTOR);

        assert(iFILSupply - iFIL.totalSupply() == sharesToBurn);
        assert(sharesBurned == sharesToBurn);
    }

    // Test to verify withdrawal of assets with alternative recipient
    function echtest_withdrawalAlternativeRecipient(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        uint256 investorBalanceInitial = wFIL.balanceOf(INVESTOR);

        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        uint256 user1BalanceInitial = wFIL.balanceOf(USER1);

        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        hevm.prank(INVESTOR);
        poolWithdrawN(withdrawAmount, USER1, INVESTOR);

        assert(wFIL.balanceOf(USER1) == withdrawAmount + user1BalanceInitial);
        assert(wFIL.balanceOf(INVESTOR) == investorBalanceInitial);
    }

    // Test to verify withdrawal updates accounting correctly
    function echtest_withdrawUpdatesAccounting(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        uint256 initialTotalAssets = pool.totalAssets();

        hevm.prank(INVESTOR);
        poolWithdrawN(withdrawAmount, INVESTOR, INVESTOR);

        // Assert total assets after withdrawal
        assert(pool.totalAssets() == initialTotalAssets - withdrawAmount);
    }

    // Test to verify withdrawal with insufficient liquidity reverts
    function echtest_withdrawRevertsOnInsufficientApprovedLiquidity(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        hevm.deal(INVESTOR, stakeAmount);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn - 1);

        // Attempt to withdraw more assets than available
        hevm.prank(INVESTOR);
        poolWithdrawReverts(withdrawAmount, INVESTOR, INVESTOR);
    }

    // Test to verify withdrawal with invalid receiver reverts
    function echtest_withdrawRevertsWithInvalidReceiver(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        // Attempt to withdraw to an invalid receiver
        hevm.prank(INVESTOR);
        poolWithdrawReverts(withdrawAmount, address(0), INVESTOR);
    }

    // Test to verify withdrawal when contract is paused
    function echtest_withdrawRevertsWhenPaused(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(stakeAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        IPausable(address(pool)).pause();

        // Attempt to withdraw while paused
        hevm.prank(INVESTOR);
        poolWithdrawReverts(stakeAmount, INVESTOR, INVESTOR);

        // Needed to reset the state to not affect the rest of the tests
        IPausable(address(pool)).unpause();
    }

    // // ============================================
    // // ==               WITHDRAWF                 ==
    // // ============================================

    // Test to verify multiple consecutive withdrawals
    function echtest_multipleConsecutiveWithdrawals(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 maxWithdraw = pool.maxWithdraw(INVESTOR);
        uint256 sharesToBurn = pool.previewWithdraw(maxWithdraw);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);

        // Withdraw first part
        hevm.prank(INVESTOR);
        poolWithdrawF(maxWithdraw / 3, INVESTOR, INVESTOR);

        // Withdraw second part
        hevm.prank(INVESTOR);
        poolWithdrawF(maxWithdraw / 3, INVESTOR, INVESTOR);

        // Withdraw third part
        hevm.prank(INVESTOR);
        poolWithdrawF(maxWithdraw / 3, INVESTOR, INVESTOR);

        assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance);
    }

       // Test to verify withdrawal when contract is paused
    function echtest_withdrawFRevertsWhenPaused(uint256 stakeAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(stakeAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        IPausable(address(pool)).pause();

        // Attempt to withdraw while paused
        hevm.prank(INVESTOR);
        poolWithdrawFReverts(stakeAmount, INVESTOR, INVESTOR);

        // Needed to reset the state to not affect the rest of the tests
        IPausable(address(pool)).unpause();
    }

    // Test for withdrawal reverts with invalid receiver
    function echtest_withdrawFRevertsWithInvalidReceiver(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn);

        // Attempt to withdraw to an invalid receiver
        hevm.prank(INVESTOR);
        poolWithdrawFReverts(withdrawAmount, address(0), INVESTOR);
    }

    // Test to verify InsufficientLiquidity revert
    function echtest_withdrawFRevertsOnInsufficientApprovedLiquidity(uint256 stakeAmount, uint256 withdrawAmount) public {
        if (stakeAmount < WAD || stakeAmount > MAX_FIL / 2) return;
        if (withdrawAmount == 0 || withdrawAmount > stakeAmount) return;

        hevm.deal(INVESTOR, stakeAmount);
        hevm.prank(INVESTOR);
        poolDepositNativeFil(stakeAmount, INVESTOR);

        uint256 sharesToBurn = pool.previewWithdraw(withdrawAmount);
        hevm.prank(INVESTOR);
        iFIL.approve(address(pool), sharesToBurn - 1);

        // Attempt to withdraw more assets than available
        hevm.prank(INVESTOR);
        poolWithdrawFReverts(withdrawAmount, INVESTOR, INVESTOR);
    }
}
