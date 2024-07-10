// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";

contract EchidnaInfinityPoolV2 is EchidnaSetup {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    constructor() payable {}

    // CoreTestHelper assertions
    function assertPegInTact() internal view {
        IMiniPool _pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));
        uint256 FILtoIFIL = _pool.convertToShares(WAD);
        uint256 IFILtoFIL = _pool.convertToAssets(WAD);
        assert(FILtoIFIL == IFILtoFIL);
        assert(FILtoIFIL == WAD);
        assert(IFILtoFIL == WAD);
    }

    // ============================================
    // ==               DEPOSIT                  ==
    // ============================================

    function test_deposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1e18, MAX_FIL / 2);

        // first make sure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 investorIFILBalBefore = iFIL.balanceOf(INVESTOR);
        uint256 iFILSupply = iFIL.totalSupply();
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));

        // here we split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        pool.deposit{value: stakeAmount}(INVESTOR);
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 previewDeposit = pool.previewDeposit(stakeAmount * 2);

        assert(investorBalBefore - (stakeAmount * 2) == wFIL.balanceOf(INVESTOR) + INVESTOR.balance);
        assert(poolBalBefore + stakeAmount * 2 == wFIL.balanceOf(address(pool)));
        assert(iFIL.balanceOf(INVESTOR) == previewDeposit + investorIFILBalBefore);
        assert(iFIL.totalSupply() == iFILSupply + previewDeposit);
    }

    function test_investorPoolBalanceAfterDeposit(uint256 stakeAmount) public {
        //@audit =>
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        uint256 sharesFirstDeposit = pool.deposit{value: stakeAmount}(INVESTOR);

        // Assert that investor and pool balances are as expected
        assert(sharesFirstDeposit == stakeAmount);
    }

    function test_totalSupplyInvariantAfterBoundDeposit(uint256 stakeAmount) public {
        //@audit => Individuals do not fail
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is sufficiently funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorFILBalStart = INVESTOR.balance; //@audit => balance
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        assertPegInTact();

        // Debugging outputs to trace values
        Debugger.log("investorWFILBalStart", investorWFILBalStart);
        Debugger.log("poolWFILBalStart", poolWFILBalStart);
        Debugger.log("investorWFILBalStart + poolWFILBalStart", (investorWFILBalStart + poolWFILBalStart));
        Debugger.log("wFIL.totalSupply()", wFIL.totalSupply());

        // Check wFIL invariant
        assert(investorWFILBalStart + poolWFILBalStart == wFIL.totalSupply());
    }

    // Test that depositing zero amount reverts the transaction
    function test_zeroDepositReverts() public {
        uint256 stakeAmount = 0;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing 0 reverts
        hevm.prank(INVESTOR);
        (bool success,) =
            address(pool).call{value: stakeAmount}(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);

        hevm.prank(INVESTOR);
        (success,) = address(pool).call(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    // Test that balances remain unchanged when attempting to deposit zero amount
    function test_balancesUnchangedAfterZeroDeposit() public {
        uint256 stakeAmount = 0;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorFILBalStart = INVESTOR.balance;
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        // Verify balances remain unchanged
        assert(investorWFILBalStart == wFIL.balanceOf(INVESTOR));
        assert(investorFILBalStart == INVESTOR.balance);
        assert(investorIFILBalStart == iFIL.balanceOf(INVESTOR));
    }

    // Test that attempting to deposit more than balance reverts the transaction
    function test_exceedingBalanceDepositReverts() public {
        uint256 stakeAmount = 0;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Verify that depositing more than balance reverts
        hevm.prank(INVESTOR);
        (bool success,) =
            address(pool).call{value: (INVESTOR.balance) * 2}(abi.encodeWithSignature("deposit(uint256)", INVESTOR));
        assert(!success);

        hevm.prank(INVESTOR);
        (success,) = address(pool).call(abi.encodeWithSignature("deposit(uint256, address)", stakeAmount, INVESTOR));
        assert(!success);
    }

    // Test to ensure correct shares are issued after deposit
    function test_correctSharesAfterDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);

        // Ensure 1:1 iFIL to FIL received
        uint256 sharesFirstDeposit = pool.deposit{value: stakeAmount}(INVESTOR);

        // Assert the correct shares are issued
        assert(sharesFirstDeposit == stakeAmount);
        assert(sharesFirstDeposit == iFIL.balanceOf(INVESTOR) - investorIFILBalStart);
        assert(investorWFILBalStart == wFIL.balanceOf(INVESTOR));
    }

    // Test to ensure correct shares are issued after a second deposit
    function test_correctSharesAfterSecondDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);

        uint256 sharesFirstDeposit = pool.deposit{value: stakeAmount}(INVESTOR);

        // Assert the correct shares are issued after the second deposit
        uint256 sharesSecondDeposit = pool.deposit(stakeAmount, INVESTOR);
        assert(sharesSecondDeposit == stakeAmount);
        assert(sharesSecondDeposit + sharesFirstDeposit == iFIL.balanceOf(INVESTOR) - investorIFILBalStart);
    }

    // Test to ensure wFIL balance invariant after deposit
    function test_wFILBalanceInvariantAfterDeposit(uint256 stakeAmount) public {
        //@audit => No error in coverage
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        // should have withdrawn wFIL now
        // assert(investorWFILBalStart - stakeAmount == wFIL.balanceOf(INVESTOR));
        assert(wFIL.totalSupply() == wFIL.balanceOf(address(pool)) + wFIL.balanceOf(INVESTOR));
        assert(wFIL.balanceOf(address(pool)) - poolWFILBalStart == stakeAmount * 2);
    }

    // Test to ensure approving an amount exceeding the balance reverts
    function test_approveExceedingBalanceReverts(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MAX_FIL + 1, MAX_FIL * 2); // Force stakeAmount to more than the balance

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that approving more than the balance reverts
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    // Test to ensure shares are issued correctly after deposit
    function test_sharesIssuedCorrectly(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        // Deposit wFIL
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        uint256 sharesReceived = pool.deposit{value: stakeAmount}(INVESTOR);

        // Assert shares received and balance changes
        assert(sharesReceived == stakeAmount);
        assert(iFIL.balanceOf(INVESTOR) - investorIFILBalStart == sharesReceived);
    }

    // Test to verify investor shares balance after multiple deposits
    function test_investorSharesBalanceAfterDeposits(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 investorIFILBalEnd = iFIL.balanceOf(INVESTOR);

        assert(pool.convertToAssets(investorIFILBalEnd) == (stakeAmount * 2) + investorIFILBalStart);

        assert(pool.convertToShares(stakeAmount * 2) == investorIFILBalEnd - investorIFILBalStart);

        assertPegInTact();
    }

    // Test to verify preview deposit rounding error
    function test_previewDepositRoundingError(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Perform a deposit to initialize the pool
        hevm.prank(INVESTOR);
        pool.deposit{value: 1 ether}(INVESTOR);

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

    // Test to verify asset transfer on deposit
    function test_assetTransferOnDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        // Track balances before deposit
        uint256 contractBalanceBefore = wFIL.balanceOf(address(pool));

        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Assert balance transfer
        assert(wFIL.balanceOf(address(pool)) == contractBalanceBefore + stakeAmount);
    }

    // Test to verify token minting on deposit
    function test_tokenMintingOnDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        // Track token balance before deposit
        uint256 tokenBalanceBefore = iFIL.balanceOf(INVESTOR);

        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Assert token minting
        assert(iFIL.balanceOf(INVESTOR) == tokenBalanceBefore + stakeAmount);
    }

    // Test to ensure deposit reverts when the contract is paused
    function test_depositRevertsWhenPaused(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        pool.pause();

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing while paused reverts
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call{value: stakeAmount}(
            abi.encodeWithSignature("deposit(uint256,address)", stakeAmount, INVESTOR)
        );
        assert(!success);
    }

    // Test to ensure deposit reverts with an invalid receiver
    function test_depositRevertsWithInvalidReceiver(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing to an invalid receiver reverts
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call{value: stakeAmount}(
            abi.encodeWithSignature("deposit(uint256,address)", stakeAmount, address(0))
        );
        assert(!success);
    }

    // Test to verify large deposit
    function test_largeDeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MAX_FIL / 2, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);

        // Track balances before deposit
        uint256 investorBalanceBefore = wFIL.balanceOf(INVESTOR);
        uint256 poolBalanceBefore = wFIL.balanceOf(address(pool));

        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Assert balances after large deposit
        assert(wFIL.balanceOf(INVESTOR) == investorBalanceBefore - stakeAmount);
        assert(wFIL.balanceOf(address(pool)) == poolBalanceBefore + stakeAmount);
    }

    // Test to verify revert when msg.value is 0
    function echidna_test_RevertOnZeroDeposit() public {
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);

        (bool success,) = address(pool).call{value: 0}(abi.encodeWithSignature("deposit(address)", INVESTOR));
        assert(!success);
    }

    // Test for partial deposits handling
    function test_partialDeposits(uint256 stakeAmount) public {
        //@audit => revise
        stakeAmount = bound(stakeAmount, 1, MAX_FIL / 2);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);

        // Perform initial deposit
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Track total assets before deposits
        uint256 totalAssetsBefore = pool.totalAssets();

        Debugger.log("totalAssetsBefore", totalAssetsBefore);

        // Perform first partial deposit
        hevm.prank(INVESTOR);
        pool.deposit{value: stakeAmount}(INVESTOR);

        uint256 totalAssetsAfterFirstDeposit = pool.totalAssets();

        Debugger.log("totalAssetsAfterFirstDeposit", totalAssetsAfterFirstDeposit);

        // Perform second partial deposit
        hevm.prank(INVESTOR);
        pool.deposit{value: stakeAmount}(INVESTOR);

        uint256 totalAssetsAfterSecondDeposit = pool.totalAssets();

        Debugger.log("totalAssetsAfterSecondDeposit", totalAssetsAfterSecondDeposit);

        // Calculate the total deposited amount
        uint256 totalDeposited = WAD + (stakeAmount * 2);

        Debugger.log("totalDeposited", totalDeposited);
        Debugger.log("totalAssets", pool.totalAssets());
        Debugger.log("totalAssetsBefore + totalDeposited", totalAssetsBefore + totalDeposited);

        // Assert total assets is correct
        assert(totalAssetsAfterSecondDeposit == totalAssetsBefore + totalDeposited);
    }

    // Test for handling multiple consecutive deposits
    function test_multipleConsecutiveDeposits(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL / 2);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, MAX_FIL * 3);

        // Perform initial deposit
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Track balance before deposits
        uint256 balanceBefore = pool.totalAssets();

        // Perform multiple consecutive deposits
        for (uint256 i = 0; i < 5; i++) {
            hevm.prank(INVESTOR);
            pool.deposit{value: stakeAmount}(INVESTOR);
        }

        // Assert total balance is correct
        assert(pool.totalAssets() == balanceBefore + (stakeAmount * 5));
    }

    // ============================================
    // ==               WITHDRAW                 ==
    // ============================================

    // Test to verify successful withdrawal of assets
    function test_successfulWithdrawal(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);
        uint256 initialPoolBalance = wFIL.balanceOf(address(pool));

        // Withdraw assets
        uint256 withdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdraw(withdrawAmount, INVESTOR, INVESTOR);

        // Assert balances after withdrawal
        assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - withdrawAmount);
        assert(wFIL.balanceOf(address(pool)) == initialPoolBalance + withdrawAmount);
    }

    // Test to verify withdrawal with insufficient liquidity reverts
    function test_withdrawRevertsOnInsufficientLiquidity(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Attempt to withdraw more assets than available
        uint256 withdrawAmount = pool.totalAssets() + 1;
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", withdrawAmount, INVESTOR, INVESTOR)
        );
        assert(!success);
    }

    // Test to verify withdrawal updates accounting correctly
    function test_withdrawUpdatesAccounting(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialTotalAssets = pool.totalAssets();

        // Withdraw assets
        uint256 withdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdraw(withdrawAmount, INVESTOR, INVESTOR);

        // Assert total assets after withdrawal
        assert(pool.totalAssets() == initialTotalAssets - withdrawAmount);
    }

    // Test to verify withdrawal with invalid receiver reverts
    function test_withdrawRevertsWithInvalidReceiver(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Attempt to withdraw to an invalid receiver
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", stakeAmount, address(0), INVESTOR)
        );
        assert(!success);
    }

    // Test to verify partial withdrawal
    function test_partialWithdrawal(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 2, MAX_FIL); // Ensure stakeAmount is at least 2 to allow partial withdrawal

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);

        // Withdraw first half of the assets
        uint256 firstWithdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdraw(firstWithdrawAmount, INVESTOR, INVESTOR);

        uint256 investorBalanceAfterFirstWithdrawal = wFIL.balanceOf(INVESTOR);

        // Withdraw second half of the assets
        uint256 secondWithdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdraw(secondWithdrawAmount, INVESTOR, INVESTOR);

        uint256 investorBalanceAfterSecondWithdrawal = wFIL.balanceOf(INVESTOR);

        // Calculate the total withdrawn amount
        uint256 totalWithdrawn = firstWithdrawAmount + secondWithdrawAmount;

        // Assert balances after each withdrawal
        assert(investorBalanceAfterFirstWithdrawal == initialInvestorBalance - firstWithdrawAmount);
        assert(investorBalanceAfterSecondWithdrawal == investorBalanceAfterFirstWithdrawal - secondWithdrawAmount);
    }

    // Test to verify complete withdrawal
    function test_completeWithdrawal(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);
        uint256 initialPoolBalance = wFIL.balanceOf(address(pool));

        // Withdraw with conversion
        hevm.prank(INVESTOR);
        pool.withdraw(stakeAmount, INVESTOR, INVESTOR);

        // Assert balances after withdrawal with conversion
        assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - stakeAmount);
        assert(wFIL.balanceOf(address(pool)) == initialPoolBalance);
    }

    // Test to verify multiple consecutive withdrawals
    function test_multipleConsecutiveWithdrawals(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL / 2); // Ensure enough for multiple withdrawals

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount * 2}(); // Deposit twice the stakeAmount for multiple withdrawals
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount * 2);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount * 2, INVESTOR);

        uint256 initialInvestorBalance = wFIL.balanceOf(INVESTOR);

        // Withdraw first half
        hevm.prank(INVESTOR);
        pool.withdraw(stakeAmount, INVESTOR, INVESTOR);

        // Withdraw second half
        hevm.prank(INVESTOR);
        pool.withdraw(stakeAmount, INVESTOR, INVESTOR);

        // Assert balances after consecutive withdrawals
        assert(wFIL.balanceOf(INVESTOR) == initialInvestorBalance - stakeAmount * 2);
    }

    // Test to verify withdrawal with different owner and receiver
    function test_withdrawDifferentOwnerReceiver(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.deal(RECEIVER, MAX_FIL * 3); // Ensure receiver is funded for testing

        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialReceiverBalance = wFIL.balanceOf(RECEIVER);

        // Withdraw with different owner and receiver
        hevm.prank(INVESTOR);
        pool.withdraw(stakeAmount, RECEIVER, INVESTOR);

        // Assert balances after withdrawal
        assert(wFIL.balanceOf(RECEIVER) == initialReceiverBalance + stakeAmount);
    }

    // Test to verify withdrawal when contract is paused
    function test_withdrawRevertsWhenPaused(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        pool.pause();

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Attempt to withdraw while paused
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", stakeAmount, INVESTOR, INVESTOR)
        );
        assert(!success);
    }

    // Test to verify withdrawal with amount zero
    // function test_withdrawZeroAmount() public {
    //     //@audit => Can a user withdraw 0?
    //     uint256 stakeAmount = 1; // Ensure there is at least some stake

    //     // Ensure the investor is funded and has deposited
    //     hevm.deal(INVESTOR, MAX_FIL * 3);
    //     hevm.prank(INVESTOR);
    //     pool.deposit{value: WAD}(INVESTOR);

    //     hevm.prank(INVESTOR);
    //     wFIL.deposit{value: stakeAmount}();
    //     hevm.prank(INVESTOR);
    //     wFIL.approve(address(pool), stakeAmount);
    //     hevm.prank(INVESTOR);
    //     pool.deposit(stakeAmount, INVESTOR);

    //     // Attempt to withdraw zero amount
    //     hevm.prank(INVESTOR);
    //     (bool success,) =
    //         address(pool).call(abi.encodeWithSignature("withdraw(uint256,address,address)", 0, INVESTOR, INVESTOR));
    //     assert(!success);
    // }

    // ============================================
    // ==               WITHDRAWF                 ==
    // ============================================

    // Test for partial withdrawals handling
    function test_partialWithdrawals(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 2, MAX_FIL / 2); // Ensure stakeAmount is at least 2 to allow partial withdrawal

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialInvestorBalance = INVESTOR.balance;

        // Perform first partial withdrawal
        uint256 firstWithdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdrawF(firstWithdrawAmount, INVESTOR, INVESTOR);

        uint256 investorBalanceAfterFirstWithdrawal = INVESTOR.balance;

        // Perform second partial withdrawal
        uint256 secondWithdrawAmount = stakeAmount / 2;
        hevm.prank(INVESTOR);
        pool.withdrawF(secondWithdrawAmount, INVESTOR, INVESTOR);

        uint256 investorBalanceAfterSecondWithdrawal = INVESTOR.balance;

        // Calculate the total withdrawn amount
        uint256 totalWithdrawn = firstWithdrawAmount + secondWithdrawAmount;

        // Assert total balance is correct after each withdrawal
        assert(investorBalanceAfterFirstWithdrawal == initialInvestorBalance + firstWithdrawAmount);
        assert(investorBalanceAfterSecondWithdrawal == investorBalanceAfterFirstWithdrawal + secondWithdrawAmount);
    }

    // Test for withdrawal reverts when paused
    function test_withdrawFRevertsWhenPaused(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Pause the contract
        hevm.prank(SYSTEM_ADMIN);
        pool.pause();

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Simulate and verify that withdrawing while paused reverts
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdrawF(uint256,address,address)", stakeAmount, INVESTOR, INVESTOR)
        );
        assert(!success);
    }

    // Test for withdrawal reverts with invalid receiver
    function test_withdrawFRevertsWithInvalidReceiver(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Simulate and verify that withdrawing to an invalid receiver reverts
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdrawF(uint256,address,address)", stakeAmount, address(0), INVESTOR)
        );
        assert(!success);
    }

    // Test to ensure correct balance transfer after withdraw with conversion
    function test_withdrawFWithConversion(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 initialInvestorBalance = INVESTOR.balance;

        // Withdraw with conversion
        hevm.prank(INVESTOR);
        pool.withdrawF(stakeAmount, INVESTOR, INVESTOR);

        uint256 investorBalanceAfterWithdrawal = INVESTOR.balance;

        // Assert balances after withdrawal with conversion
        assert(investorBalanceAfterWithdrawal == initialInvestorBalance + stakeAmount);
    }

    // Test to verify InsufficientLiquidity revert
    function test_insufficientLiquidityRevert(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Withdraw all liquidity first
        hevm.prank(INVESTOR);
        pool.withdrawF(stakeAmount, INVESTOR, INVESTOR);

        // Try to withdraw again with insufficient liquidity
        hevm.prank(INVESTOR);
        (bool success,) = address(pool).call(
            abi.encodeWithSignature("withdrawF(uint256,address,address)", stakeAmount, INVESTOR, INVESTOR)
        );
        assert(!success);
    }

    // Test for correct asset transfer during exit
    function test_assetTransferOnExit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 contractBalanceBefore = wFIL.balanceOf(address(pool));
        uint256 investorBalanceBefore = INVESTOR.balance;

        // Withdraw with conversion
        hevm.prank(INVESTOR);
        pool.withdrawF(stakeAmount, INVESTOR, INVESTOR);

        uint256 contractBalanceAfter = wFIL.balanceOf(address(pool));
        uint256 investorBalanceAfter = INVESTOR.balance;

        // Assert asset transfer is correct
        assert(contractBalanceAfter == contractBalanceBefore - stakeAmount);
        assert(investorBalanceAfter == investorBalanceBefore + stakeAmount);
    }

    // Test for large withdrawals handling
    function test_largeWithdrawals(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, MAX_FIL / 2, MAX_FIL);

        // Ensure the investor is funded and has deposited
        hevm.deal(INVESTOR, MAX_FIL * 3);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        uint256 contractBalanceBefore = wFIL.balanceOf(address(pool));
        uint256 investorBalanceBefore = INVESTOR.balance;

        // Withdraw with conversion
        hevm.prank(INVESTOR);
        pool.withdrawF(stakeAmount, INVESTOR, INVESTOR);

        uint256 contractBalanceAfter = wFIL.balanceOf(address(pool));
        uint256 investorBalanceAfter = INVESTOR.balance;

        // Assert asset transfer is correct
        assert(contractBalanceAfter == contractBalanceBefore - stakeAmount);
        assert(investorBalanceAfter == investorBalanceBefore + stakeAmount);
    }
}
