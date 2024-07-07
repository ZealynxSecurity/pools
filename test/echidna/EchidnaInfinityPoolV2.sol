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

    // Cheatcodes helpers
    function bound(uint256 random, uint256 low, uint256 high) public pure returns (uint256) {
        return low + random % (high - low);
    }

    function test_deposit(uint256 stakeAmount) public {
        // first make sure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));
        // here we split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount / 2}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount / 2);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount / 2, INVESTOR);

        assert(wFIL.balanceOf(INVESTOR) + INVESTOR.balance - stakeAmount == investorBalBefore);
        assert(poolBalBefore + stakeAmount == wFIL.balanceOf(address(pool)));
    }

    function test_depositBalance(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 0, MAX_FIL);

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorBalBefore = wFIL.balanceOf(INVESTOR) + INVESTOR.balance;
        uint256 poolBalBefore = wFIL.balanceOf(address(pool));

        // Split the stakeAmount into wFIL and FIL for testing purposes
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount / 2}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount / 2);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount / 2, INVESTOR);

        // Assert that investor and pool balances are as expected
        assert(wFIL.balanceOf(INVESTOR) + INVESTOR.balance - stakeAmount == investorBalBefore);
        assert(poolBalBefore + stakeAmount == wFIL.balanceOf(address(pool)));
    }

    function test_bounddeposit(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL);

        // Ensure the investor is sufficiently funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        uint256 investorFILBalStart = INVESTOR.balance;
        uint256 investorWFILBalStart = wFIL.balanceOf(INVESTOR);
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);
        uint256 poolWFILBalStart = wFIL.balanceOf(address(pool));

        assertPegInTact();

        // Check wFIL invariant
        // assert(investorWFILBalStart + poolWFILBalStart == wFIL.totalSupply());
    }

    function test_depositZeroReverts() public {
        uint256 stakeAmount = 0;

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
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

    function test_fuzz_depositMoreThanBalanceReverts(uint256 stakeAmount) public {
        // Ensure stakeAmount is between 1.5 and 2 times MAX_FIL to force the condition
        stakeAmount = bound(stakeAmount, MAX_FIL + 1, MAX_FIL * 2);

        // Ensure the investor is funded with sufficient balance for deposits
        hevm.deal(INVESTOR, MAX_FIL + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Simulate and verify that depositing more than the available balance reverts
        hevm.prank(INVESTOR);
        (bool success,) =
            address(pool).call{value: stakeAmount}(abi.encodeWithSignature("deposit(uint256)", stakeAmount));
        assert(!success);
    }

    function test_fuzz_approveMoreThanBalanceReverts(uint256 stakeAmount) public {
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

    function test_fuzz_sharesReceivedAfterDeposit(uint256 stakeAmount) public {
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

    function test_fuzz_filiFILProportion(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 1, MAX_FIL); // Ensure stakeAmount is not 0

        // Ensure the investor is funded
        hevm.deal(INVESTOR, stakeAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: WAD}(INVESTOR);

        // Get initial iFIL balance of investor
        uint256 investorIFILBalStart = iFIL.balanceOf(INVESTOR);

        // Deposit wFIL
        hevm.prank(INVESTOR);
        wFIL.deposit{value: stakeAmount}();
        hevm.prank(INVESTOR);
        wFIL.approve(address(pool), stakeAmount);
        hevm.prank(INVESTOR);
        pool.deposit(stakeAmount, INVESTOR);

        // Get final iFIL balance of investor
        uint256 investorIFILBalEnd = iFIL.balanceOf(INVESTOR);

        // Assert the final balance is greater than the initial balance
        assert(investorIFILBalEnd > investorIFILBalStart);

        // Verify FIL and iFIL proportions
        uint256 assetsConverted = pool.convertToAssets(investorIFILBalEnd);
        uint256 sharesConverted = pool.convertToShares(investorIFILBalEnd - investorIFILBalStart);

        // Assert the converted assets and shares
        assert(assetsConverted == investorIFILBalEnd);
        assert(sharesConverted == (investorIFILBalEnd - investorIFILBalStart));
    }
}
