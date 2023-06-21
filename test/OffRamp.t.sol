// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

import "./BaseTest.sol";

contract OffRampTest is BaseTest {

  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;
  using AccountHelpers for Account;

  IAgent agent;
  uint64 miner;
  IPool pool;
  IPoolToken iFIL;
  IOffRamp ramp;

  address investor1 = makeAddr("INVESTOR");
  address minerOwner = makeAddr("MINER_OWNER");

  function setUp() public {
    pool = createPool();
    iFIL = pool.liquidStakingToken();
    (agent, miner) = configureAgent(minerOwner);

    // configure the offramp
    ramp = new InfPoolSimpleRamp(router, pool.id());

    vm.startPrank(systemAdmin);
    pool.setRamp(ramp);
    // set no fees to simplify test accounting 
    GetRoute.poolRegistry(router).setTreasuryFeeRate(0);
    iFIL.setBurner(address(ramp));
    vm.stopPrank();

    assertEq(address(pool.ramp()), address(ramp), "Ramp not set");
  }

  function testExitReserve(uint256 exitReservePercent, uint256 stakeAmount, uint256 borrowAmount) public {
    // bound between 0 exit reserves and 100% exit reserves
    exitReservePercent = bound(exitReservePercent, 0, 1e18);
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    borrowAmount = bound(borrowAmount, WAD, stakeAmount);

    setMinLiquidity(exitReservePercent);
    fundPoolByInvestor(stakeAmount, investor1);
    borrowFromPool(borrowAmount, stakeAmount);
  }

  function testWithdrawRedeemThroughPool() public {
    fundPoolByInvestor(100e18, investor1);

    vm.startPrank(investor1);
    uint256 maxWithdraw = pool.maxWithdraw(investor1);
    uint256 maxRedeem = pool.maxRedeem(investor1);
    vm.expectRevert(Unauthorized.selector);
    pool.withdraw(maxWithdraw, investor1, investor1);

    vm.expectRevert(Unauthorized.selector);
    pool.redeem(maxRedeem, investor1, investor1);
  }

  function testWithdrawAlternativeRecipient(uint256 stakeAmount, uint256 withdrawAmount, string memory addressSeed) public {
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    withdrawAmount = bound(withdrawAmount, WAD, stakeAmount);

    address receiver = makeAddr(addressSeed);

    fundPoolByInvestor(stakeAmount, investor1);

    vm.startPrank(investor1);
    uint256 iFILSupply = iFIL.totalSupply();
    uint256 sharesToBurn = pool.convertToShares(withdrawAmount);
    iFIL.approve(address(ramp), sharesToBurn);
    ramp.withdraw(withdrawAmount, receiver, investor1, 0);

    assertEq(wFIL.balanceOf(receiver), withdrawAmount, "Receiver should have received assets");
    assertEq(wFIL.balanceOf(investor1), 0, "Investor1 should not have received assets");
    vm.stopPrank();

    assertEq(iFILSupply - iFIL.totalSupply(), sharesToBurn, "iFIL should have been burned");

    assertPegInTact(pool);
  }

  function testRedeemAlternativeRecipient(uint256 stakeAmount, uint256 redeemAmount, string memory addressSeed) public {
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    redeemAmount = bound(redeemAmount, WAD, stakeAmount);

    address receiver = makeAddr(addressSeed);

    fundPoolByInvestor(stakeAmount, investor1);
    uint256 iFILSupply = iFIL.totalSupply();
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), redeemAmount);
    ramp.redeem(redeemAmount, receiver, investor1, 0);

    assertEq(wFIL.balanceOf(receiver), pool.convertToAssets(redeemAmount), "Receiver should have received assets");
    assertEq(wFIL.balanceOf(investor1), 0, "Investor1 should not have received assets");
    vm.stopPrank();

    assertEq(iFILSupply - iFIL.totalSupply(), redeemAmount, "iFIL should have been burned");

    assertPegInTact(pool);
  }

  function testSingleDepositWithdrawNoEarnings(uint256 exitReservePercent, uint256 stakeAmount, uint256 borrowAmount, uint256 withdrawAmount) public {
    // bound between 0 exit reserves and 100% exit reserves
    exitReservePercent = bound(exitReservePercent, 0, 1e18);
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    borrowAmount = bound(borrowAmount, WAD, stakeAmount);
    withdrawAmount = bound(withdrawAmount, 0, stakeAmount);

    setMinLiquidity(exitReservePercent);
    fundPoolByInvestor(stakeAmount, investor1);
    assertEq(pool.maxWithdraw(investor1), stakeAmount, "Max withdraw incorrect");

    uint256 investorIFIL = iFIL.balanceOf(investor1);
    assertEq(investorIFIL, stakeAmount, "Investor has wrong iFIL amount");
    assertEq(address(investor1).balance, 0, "Investor should have staked all balance");
    assertEq(wFIL.balanceOf(investor1), 0, "Investor should not have any wFIL");
    uint256 iFILSupply = iFIL.totalSupply();

    borrowFromPool(borrowAmount, stakeAmount);

    uint256 exitLiquidity = pool.getLiquidAssets();
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), pool.convertToAssets(investorIFIL));

    // preview withdraw should revert 
    if (exitLiquidity < withdrawAmount) {
      assertEq(pool.previewWithdraw(withdrawAmount), 0, "preview withdraw should return 0");

      vm.expectRevert(InfPoolSimpleRamp.InsufficientLiquidity.selector);
      ramp.withdraw(withdrawAmount, investor1, investor1, 0);
    } else {
      assertEq(pool.previewWithdraw(withdrawAmount), withdrawAmount, "Wrong preview withdraw");
      uint256 sharesBurned = ramp.withdraw(withdrawAmount, investor1, investor1, 0);
      assertEq(sharesBurned, withdrawAmount, "Burn == redeem amount when iFIL still pegged");
      assertEq(wFIL.balanceOf(investor1), withdrawAmount, "Investor should have withdrawAmount wFIL");
      assertEq(iFIL.balanceOf(investor1), stakeAmount - withdrawAmount, "Investor should have stakeAmount - withdrawAmount iFIL");
      assertEq(investorIFIL - iFIL.balanceOf(investor1), sharesBurned, "Investor should have burned sharesBurned iFIL");
      assertEq(iFILSupply - withdrawAmount, iFIL.totalSupply(), "IFIL supply should have decreased by the withdraw amount");
      assertEq(wFIL.balanceOf(investor1), withdrawAmount, "Investor should have received withdrawAmount of wFIL");
    }
    vm.stopPrank();

    // since this is the only investor in the pool, they will always be able to withdraw the max liquidity
    assertEq(pool.maxWithdraw(investor1), pool.getLiquidAssets(), "Max withdraw incorrect");
    assertPegInTact(pool);
  }

  function testSingleDepositRedeemNoEarnings(uint256 exitReservePercent, uint256 stakeAmount, uint256 borrowAmount, uint256 redeemAmount) public {
    // bound between 0 exit reserves and 100% exit reserves
    exitReservePercent = bound(exitReservePercent, 0, 1e18);
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    borrowAmount = bound(borrowAmount, WAD, stakeAmount);
    redeemAmount = bound(redeemAmount, 0, stakeAmount);

    setMinLiquidity(exitReservePercent);
    fundPoolByInvestor(stakeAmount, investor1);
    // before the borrow, the maxRedeem should be the total iFIL owned by investor
    assertEq(pool.maxRedeem(investor1), stakeAmount, "Max redeem incorrect");

    uint256 investorIFIL = iFIL.balanceOf(investor1);
    assertEq(investorIFIL, stakeAmount, "Investor has wrong iFIL amount");
    assertEq(address(investor1).balance, 0, "Investor should have staked all balance");
    assertEq(wFIL.balanceOf(investor1), 0, "Investor should not have any wFIL");
    uint256 iFILSupply = iFIL.totalSupply();

    borrowFromPool(borrowAmount, stakeAmount);

    uint256 exitLiquidity = pool.getLiquidAssets();
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), pool.convertToAssets(investorIFIL));

    // preview withdraw should revert 
    if (exitLiquidity < redeemAmount) {
      assertEq(pool.previewRedeem(redeemAmount), 0, "Preview redeem should return 0");

      vm.expectRevert(InfPoolSimpleRamp.InsufficientLiquidity.selector);
      ramp.redeem(redeemAmount, investor1, investor1, 0);
    } else {
      assertEq(pool.previewRedeem(redeemAmount), redeemAmount, "Wrong preview redeem");
      uint256 assetsReceived = ramp.redeem(redeemAmount, investor1, investor1, 0);
      assertEq(assetsReceived, redeemAmount, "assets received == redeem amount when iFIL still pegged");
      assertEq(wFIL.balanceOf(investor1), redeemAmount, "Investor should have redeemAmount wFIL");
      assertEq(iFIL.balanceOf(investor1), stakeAmount - redeemAmount, "Investor should have stakeAmount - redeemAmount iFIL");
      assertEq(investorIFIL - iFIL.balanceOf(investor1), assetsReceived, "Investor should have burned sharesBurned iFIL");
      assertEq(iFILSupply - redeemAmount, iFIL.totalSupply(), "IFIL supply should have decreased by the redeem amount");
      assertEq(wFIL.balanceOf(investor1), redeemAmount, "Investor should have received redeemAmount of wFIL");
    }
    vm.stopPrank();

    // since this is the only investor in the pool, they will always be able to redeem the max liquidity
    assertEq(pool.maxRedeem(investor1), pool.getLiquidAssets(), "Max redeem incorrect");
    assertPegInTact(pool);
  }

  function testSingleDepositWithdrawWithEarnings(uint256 stakeAmount, uint256 earningsAmount, uint256 withdrawAmount) public {
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    earningsAmount = bound(earningsAmount, 1, MAX_FIL);
    withdrawAmount = bound(withdrawAmount, 1, stakeAmount);

    // set exit reserves to 10%
    setMinLiquidity(1e17);
    fundPoolByInvestor(stakeAmount, investor1);
    uint256 totalIFIL = iFIL.totalSupply();

    assertEq(wFIL.balanceOf(investor1), 0, "Investor should not have wFIL");

    simulateEarnings(earningsAmount);
    // max withdraw should report the full amount + earnings since this is the only staker
    assertEq(pool.maxWithdraw(investor1), stakeAmount + earningsAmount, "Max withdraw incorrect");
    // previewWithdraw should incorporate the earnings
    // here the correct amount of shares to burn must use the correct asset price
    uint256 sharesToBurn = pool.convertToShares(withdrawAmount);
    assertEq(pool.previewWithdraw(withdrawAmount), sharesToBurn, "preview withdraw incorrect after earnings");
    uint256 investorIFIL = iFIL.balanceOf(investor1);
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), sharesToBurn);
    uint256 sharesBurned = ramp.withdraw(withdrawAmount, investor1, investor1, 0);
    vm.stopPrank();
    assertEq(sharesBurned, sharesToBurn, "Incorrect burn amount");
    assertGt(withdrawAmount, sharesToBurn, "Withdraw amount should have been greater than shares burned after earnings");
    assertEq(investorIFIL - iFIL.balanceOf(investor1), sharesToBurn, "Investor should have burned sharesToBurn iFIL");
    assertEq(totalIFIL - iFIL.totalSupply(), sharesBurned);
    assertEq(wFIL.balanceOf(investor1), withdrawAmount, "Investor should have received withdrawAmount of wFIL");

    // withdraw the rest
    uint256 maxWithdraw = pool.maxWithdraw(investor1);
    uint256 iFILBal = iFIL.balanceOf(investor1);
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), iFILBal);
    sharesBurned = ramp.withdraw(maxWithdraw, investor1, investor1, 0);
    vm.stopPrank();

    assertEq(sharesBurned, iFILBal, "maxWithdraw should have burned rest of investors iFIL bal");
    assertEq(wFIL.balanceOf(investor1), stakeAmount + earningsAmount, "investor should have all the earnings");
    assertCompleteExit();
  }

  function testSingleDepositRedeemWithEarnings(uint256 stakeAmount, uint256 earningsAmount, uint256 redeemAmount) public {
    stakeAmount = bound(stakeAmount, WAD, MAX_FIL);
    earningsAmount = bound(earningsAmount, 1, MAX_FIL);
    
    redeemAmount = bound(redeemAmount, 1, stakeAmount / 3);

    // set exit reserves to 10%
    setMinLiquidity(1e17);
    fundPoolByInvestor(stakeAmount, investor1);
    uint256 totalIFIL = iFIL.totalSupply();

    assertEq(wFIL.balanceOf(investor1), 0, "Investor should not have wFIL");

    simulateEarnings(earningsAmount);
    // max redeem should report the full iFIL holdings of this staker
    assertEq(pool.maxRedeem(investor1), totalIFIL, "Max redeem incorrect");
    // previewRedeem should incorporate the earnings
    // here the correct amount of shares to burn must use the correct asset price
    uint256 assetsToReceive = pool.convertToAssets(redeemAmount);
    assertEq(pool.previewRedeem(redeemAmount), assetsToReceive, "preview redeem incorrect after earnings");
    uint256 investorIFIL = iFIL.balanceOf(investor1);
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), redeemAmount);
    uint256 assetsReceived = ramp.redeem(redeemAmount, investor1, investor1, 0);
    vm.stopPrank();
    assertEq(assetsReceived, assetsToReceive, "Incorrect burn amount");
    // here we add 1 to the assetsToReceive in tiny amounts due to rounding, creating equivolency 
    assertGt(assetsToReceive + 1, redeemAmount, "Assets received amount should have been greater than redeem amount after earnings");
    assertEq(investorIFIL - iFIL.balanceOf(investor1), redeemAmount, "Investor should have burned redeemAmount iFIL");
    assertEq(totalIFIL - iFIL.totalSupply(), redeemAmount);
    assertEq(wFIL.balanceOf(investor1), assetsToReceive, "Investor should have received withdrawAmount of wFIL");

    // withdraw the rest
    uint256 maxRedeem = pool.maxRedeem(investor1);
    uint256 iFILBal = iFIL.balanceOf(investor1);
    vm.startPrank(investor1);
    iFIL.approve(address(ramp), iFILBal);
    assertEq(maxRedeem, iFILBal, "Max redeem should return the rest of the investors iFIL");
    uint256 assetsReceivedAfterFullExit = ramp.redeem(maxRedeem, investor1, investor1, 0);
    vm.stopPrank();

    assertEq(assetsReceivedAfterFullExit, stakeAmount + earningsAmount - assetsReceived, "maxRedeem should have returned investors full amount");
    assertEq(wFIL.balanceOf(investor1), stakeAmount + earningsAmount, "investor should have all the earnings");
    assertCompleteExit();
  }

  function testMultiDepositWithdrawKnownCase() public {
    uint256 stakeAmount = WAD;

    address depositor1 = makeAddr("DEPOSITOR1");
    address depositor2 = makeAddr("DEPOSITOR2");
    fundPoolByInvestor(stakeAmount, depositor1);
    fundPoolByInvestor(stakeAmount, depositor2);

    uint256 earningsAmount = 82772074349669417149057;

    assertEq(pool.getLiquidAssets(), 2e18, "Wrong stake amount");
    simulateEarnings(earningsAmount);

    // withdraw the max amount for each depositor
    assertEq(wFIL.balanceOf(depositor1), 0, "Depositor should not have wFIL");
    vm.startPrank(depositor1);
    uint256 maxWithdraw = pool.maxWithdraw(depositor1);
    iFIL.approve(address(ramp), pool.convertToShares(maxWithdraw));
    ramp.withdraw(maxWithdraw, depositor1, depositor1, 0);
    vm.stopPrank();

    assertEq(wFIL.balanceOf(depositor2), 0, "Depositor should not have wFIL");
    vm.startPrank(depositor2);
    maxWithdraw = pool.maxWithdraw(depositor2);
    iFIL.approve(address(ramp), pool.convertToShares(maxWithdraw));
    ramp.withdraw(maxWithdraw, depositor2, depositor2, 0);
    vm.stopPrank();

    assertCompleteExit();
  }

  function testMultiDepositWithdraw(uint256 numDepositors, uint256 earningsAmount) public {
    numDepositors = bound(numDepositors, 1, 500);
    earningsAmount = bound(earningsAmount, 1, MAX_FIL);

    // every depositor stakes stake amount
    uint256 stakeAmount = WAD;

    for (uint256 i = 0; i < numDepositors; i++) {
      address depositor = makeAddr(vm.toString(i));
      fundPoolByInvestor(stakeAmount, depositor);
    }
    assertEq(pool.totalAssets(), pool.getLiquidAssets(), "total assets wrong");
    assertEq(pool.totalAssets(), pool.totalBorrowableAssets(), "total borrowable assets wrong");
    assertEq(pool.getLiquidAssets(), numDepositors * stakeAmount, "Wrong stake amount");

    assertPegInTact(pool);
    simulateEarnings(earningsAmount);

    // withdraw the max amount for each depositor
    for (uint256 j = 0; j < numDepositors; j++) {
      address depositor = makeAddr(vm.toString(j));
      assertEq(wFIL.balanceOf(depositor), 0, "Depositor should not have wFIL");
      vm.startPrank(depositor);
      uint256 maxWithdraw = pool.maxWithdraw(depositor);
      uint256 iFILBal = iFIL.balanceOf(depositor);
      // add one for rounding dust
      assertApproxEqRel(maxWithdraw, stakeAmount + (earningsAmount / numDepositors), 1e2, "Max withdraw should be greater than amount staked after earnings");
      iFIL.approve(address(ramp), pool.convertToShares(maxWithdraw));
      uint256 sharesBurnt = ramp.withdraw(maxWithdraw, depositor, depositor, 0);
      assertApproxEqAbs(sharesBurnt, iFILBal, 1, "Max withdraw should burn all of the investors iFIL");
      assertApproxEqRel(wFIL.balanceOf(depositor), stakeAmount + (earningsAmount) / numDepositors, 1e2, "Depositor should have earned rewards");
      vm.stopPrank();
    }

    assertCompleteExit();
  }

  function testMultiDepositRedeem(uint256 numDepositors, uint256 earningsAmount) public {
    numDepositors = bound(numDepositors, 1, 500);
    earningsAmount = bound(earningsAmount, 1, MAX_FIL);

    // every depositor stakes stake amount
    uint256 stakeAmount = WAD;

    for (uint256 i = 0; i < numDepositors; i++) {
      address depositor = makeAddr(vm.toString(i));
      fundPoolByInvestor(stakeAmount, depositor);
    }
    assertEq(pool.totalAssets(), pool.getLiquidAssets(), "total assets wrong");
    assertEq(pool.totalAssets(), pool.totalBorrowableAssets(), "total borrowable assets wrong");
    assertEq(pool.getLiquidAssets(), numDepositors * stakeAmount, "Wrong stake amount");

    assertPegInTact(pool);
    simulateEarnings(earningsAmount);

    // withdraw the max amount for each depositor
    for (uint256 j = 0; j < numDepositors; j++) {
      address depositor = makeAddr(vm.toString(j));
      assertEq(wFIL.balanceOf(depositor), 0, "Depositor should not have wFIL");
      vm.startPrank(depositor);
      uint256 maxRedeem = pool.maxRedeem(depositor);
      uint256 iFILBal = iFIL.balanceOf(depositor);
      // add one for rounding dust
      assertEq(maxRedeem, iFILBal, "Max redeem should equal depositor ifil bal");
      iFIL.approve(address(ramp), maxRedeem);
      uint256 assetsReceived = ramp.redeem(maxRedeem, depositor, depositor, 0);
      assertApproxEqAbs(assetsReceived, stakeAmount + (earningsAmount / numDepositors), 1, "Max redeem should net depositor correct assets");
      assertApproxEqRel(wFIL.balanceOf(depositor), stakeAmount + (earningsAmount) / numDepositors, 1e2, "Depositor should have earned rewards");
      vm.stopPrank();
    }

    assertCompleteExit();
  }

  function testRecoverFIL(uint256 recoverAmount) public {
    vm.assume(recoverAmount < MAX_FIL);

    address donator = makeAddr("DONATOR");

    vm.deal(donator, recoverAmount);
    vm.startPrank(donator);
    wFIL.deposit{value: recoverAmount}();
    wFIL.transfer(address(ramp), recoverAmount);
    // transfer FIL to ramp
    vm.deal(address(ramp), recoverAmount);

    assertEq(wFIL.balanceOf(address(ramp)), recoverAmount, "Ramp should have received recoverAmount/2 of wFIL");
    assertEq(address(ramp).balance, recoverAmount, "Ramp should have received recoverAmount/2 of FIL");
    assertEq(wFIL.balanceOf(address(pool)), 0, "Pool should not have WFIL");
    assertEq(address(pool).balance, 0, "Pool should not have FIL");

    ramp.recoverFIL();

    assertEq(wFIL.balanceOf(address(ramp)), 0, "Ramp should not have WFIL after recovery");
    assertEq(address(pool).balance, 0, "Ramp should not have FIL after recovery");
    // we recovered FIL and wFIL in recoverAmount, which is why we multiply by 2 here
    assertEq(wFIL.balanceOf(address(pool)), recoverAmount * 2, "Pool should have assets");
    assertEq(address(pool).balance, 0, "Pool should have 0 FIL after recovery");
  }

  function setMinLiquidity(uint256 minLiquidity) internal {
    vm.prank(systemAdmin);
    pool.setMinimumLiquidity(minLiquidity);
    assertEq(pool.minimumLiquidity(), minLiquidity, "Exit reserve not set");
  }

  function fundPoolByInvestor(uint256 amount, address investor) internal {
    vm.deal(investor, amount);
    vm.prank(investor);
    pool.deposit{value: amount}(investor);
    assertPegInTact(pool);
  }

  function borrowFromPool(uint256 borrowAmount, uint256 stakeAmount) internal {
    uint256 reserveAbs = stakeAmount.mulWadUp(pool.minimumLiquidity());

    // the total amount of FIL reserved for exits should be equal to exit reserve percent * stake amount
    assertEq(pool.getAbsMinLiquidity(), reserveAbs, "Exit reserve wrong");
    assertEq(pool.totalBorrowableAssets(), stakeAmount - reserveAbs, "Total borrowable liquidity wrong");
    assertEq(pool.getLiquidAssets(), stakeAmount, "Liquid assets wrong");

    SignedCredential memory sc = issueGenericBorrowCred(agent.id(), borrowAmount);

    vm.startPrank(minerOwner);
    uint256 poolID = pool.id();
    
    if (borrowAmount > stakeAmount - reserveAbs) {
      vm.expectRevert(InfinityPool.InsufficientLiquidity.selector);
      agent.borrow(poolID, sc);
    } else {
      agent.borrow(poolID, sc);
      assertEq(pool.getAbsMinLiquidity(), reserveAbs, "Exit reserve wrong");
      assertEq(pool.totalBorrowableAssets(), stakeAmount - reserveAbs - borrowAmount, "Total borrowable liquidity wrong");
      assertEq(pool.getLiquidAssets(), stakeAmount - borrowAmount, "Liquid assets wrong");
    }
    vm.stopPrank();
  }

  function simulateEarnings(uint256 earnAmount) internal {
    address donator = makeAddr("DONATOR");
    vm.deal(donator, earnAmount);
    vm.startPrank(donator);
    wFIL.deposit{value: earnAmount}();
    wFIL.transfer(address(pool), earnAmount);
    vm.stopPrank();
  }

  function assertCompleteExit() internal {
    assertLt(iFIL.totalSupply(), 1e10, "There should be no iFIL left to burn");
    assertEq(iFIL.balanceOf(investor1), 0, "Investor should have no iFIL left to burn");
    // here we assert that the complete exit means theres less than 1 FIL left in the pool 
    assertLt(wFIL.balanceOf(address(pool)), 1e10, "Pool should have no assets left");
    assertLt(pool.getLiquidAssets(), 1e10, "Pool should have no liquid assets");
    assertLt(pool.totalBorrowableAssets(), 1e10, "Pool should have no borrowable assets");
  }
}
