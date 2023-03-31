// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";

import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";

contract PoolTestState is BaseTest {
  error InvalidParams();
  error InvalidState();

  using Credentials for VerifiableCredential;
  IPool pool;
  IPoolFactory poolFactory;
  uint256 borrowAmount = WAD;
  uint256 stakeAmount = 1000e18;
  uint256 expectedRateBasic = 15e18;
  uint256 goodEDR = .01e18;
  address investor1 = makeAddr("INVESTOR_1");
  address minerOwner = makeAddr("MINER_OWNER");
  uint256 gCredBasic;
  SignedCredential borrowCredBasic;
  VerifiableCredential vcBasic;
  IAgent agent;
  uint64 miner;
  uint256 baseRate;
  IPoolToken public liquidStakingToken;
  IERC20 public asset;
  uint256 agentID;
  uint256 poolID;
  IOffRamp ramp;
  IPoolToken iou;

  function setUp() public virtual {
    (pool, agent, miner, borrowCredBasic, vcBasic, gCredBasic, baseRate) = PoolBasicSetup(
      stakeAmount,
      borrowAmount,
      investor1,
      minerOwner
    );
    poolFactory = GetRoute.poolFactory(router);
    asset = pool.asset();
    liquidStakingToken = pool.liquidStakingToken();
    agentID = agent.id();
    poolID = pool.id();
  }

  function loadWFIL(uint256 amount, address investor) internal {
    vm.deal(investor, amount);
    vm.prank(investor);
    wFIL.deposit{value: amount}();
  }

  function loadApproveWFIL(uint256 amount, address investor) internal {
    loadWFIL(amount, investor);
    vm.prank(investor);
    wFIL.approve(address(pool), amount);
  }

  function _setupRamp() internal {
    ramp = _configureOffRamp(pool);
    // Confirm there's no balance on the ramp to begin with
    assertEq(asset.balanceOf(address(ramp)), 0);
    vm.prank(systemAdmin);
    pool.setRamp(IOffRamp(ramp));
    iou = IPoolToken(ramp.iouToken());
  }


  function _mintApproveIOU(uint256 amount, address target, address spender) internal {
    vm.prank(address(ramp));
    iou.mint(target, amount);
    vm.prank(target);
    iou.approve(address(spender), amount);
  }

  function _mintApproveLST(uint256 amount, address target, address spender) internal {
    vm.prank(address(pool));
    liquidStakingToken.mint(target, amount);
    vm.prank(target);
    liquidStakingToken.approve(address(spender), amount);
  }

  function _stakeToRamp(uint256 amount, address staker) internal {
    vm.startPrank(investor1);
    // Finally, we can stake & harvest after setup
    ramp.stake(amount);
  }

}

contract PoolBasicSetupTest is BaseTest {
  using Credentials for VerifiableCredential;

  IPool pool;
  uint256 borrowAmount = WAD;
  uint256 stakeAmount = 1000e18;
  uint256 expectedRateBasic = 15e18;
  uint256 goodEDR = .01e18;
  address investor1 = makeAddr("INVESTOR_1");
  address minerOwner = makeAddr("MINER_OWNER");
  uint256 gCredBasic;
  SignedCredential borrowCredBasic;
  VerifiableCredential vcBasic;
  IAgent agent;
  uint64 miner;
  uint256 baseRate;

  function testCreatePool() public {
    IPoolFactory poolFactory = GetRoute.poolFactory(router);
    PoolToken liquidStakingToken = new PoolToken("LIQUID", "LQD",systemAdmin, systemAdmin);
    uint256 id = poolFactory.allPoolsLength();
    address rateModule = address(new RateModule(systemAdmin, systemAdmin, router, rateArray));
    pool = IPool(new GenesisPool(
      systemAdmin,
      systemAdmin,
      router,
      address(wFIL),
      //
      rateModule,
      // no min liquidity for test pool
      address(liquidStakingToken),
      0
    ));
    assertEq(pool.id(), id, "pool id not set");
    assertEq(address(pool.asset()), address(wFIL), "pool asset not set");
    assertEq(IAuth(address(pool)).owner(), systemAdmin, "pool owner not set");
    assertEq(address(pool.rateModule()), rateModule, "pool rate module not set");
    assertEq(address(pool.liquidStakingToken()), address(liquidStakingToken), "pool liquid staking token not set");
    assertEq(pool.minimumLiquidity(), 0, "pool min liquidity not set");
    vm.prank(systemAdmin);
    liquidStakingToken.setMinter(address(pool));
    vm.startPrank(systemAdmin);
    // After the pool has been attached to the factory the count should change
    poolFactory.attachPool(pool);
    assertEq(poolFactory.allPoolsLength(), id + 1, "pool not added to allPools");
    vm.stopPrank();
  }
}

contract PoolDepositTest is PoolTestState {
  function testDepositBasic() public {
    uint256 amount = WAD;
    uint256 balanceBefore = wFIL.balanceOf(address(pool));
    uint256 lstBalanceBefore = pool.liquidStakingToken().balanceOf(address(investor1));
    uint256 predictedLST = pool.previewDeposit(amount);
    loadApproveWFIL(amount, investor1);
    vm.prank(investor1);
    pool.deposit(amount, investor1);
    uint256 balanceAfter = wFIL.balanceOf(address(pool));
    assertEq(balanceAfter, balanceBefore + amount, "deposit failed - wrong WFIL balance");
    uint256 lstBalanceAfter = pool.liquidStakingToken().balanceOf(address(investor1));
    assertEq(lstBalanceAfter, lstBalanceBefore + predictedLST, "deposit failed -  wrong LST balance");
  }

  function testDepositFuzz(uint256 amount) public {
    amount = bound(amount, WAD, 1e21);
    uint256 balanceBefore = wFIL.balanceOf(address(pool));
    uint256 lstBalanceBefore = pool.liquidStakingToken().balanceOf(address(investor1));
    uint256 predictedLST = pool.previewDeposit(amount);
    loadApproveWFIL(amount, investor1);
    vm.prank(investor1);
    pool.deposit(amount, investor1);
    uint256 balanceAfter = wFIL.balanceOf(address(pool));
    assertEq(balanceAfter, balanceBefore + amount, "deposit failed - wrong WFIL balance");
    uint256 lstBalanceAfter = pool.liquidStakingToken().balanceOf(address(investor1));
    assertEq(lstBalanceAfter, lstBalanceBefore + predictedLST, "deposit failed -  wrong LST balance");
  }
}

contract PoolGetRateTest is PoolTestState {

  function testGetRateBasic() public {
    uint256 rate = pool.getRate(Account(0,0,0, true), vcBasic);
    uint256 expectedRate = baseRate * rateArray[gCredBasic] / WAD;
    assertEq(rate, expectedRate);
  }

  function testGetRateFuzz(uint256 gCRED) public {
    gCRED = bound(gCRED, 0, 99);
    AgentData memory agentData = createAgentData(
      // collateral value => 2x the borrowAmount
      borrowAmount * 2,
      // good gcred score
      gCRED,
      // good EDR
      goodEDR,
      // principal = borrowAmount
      borrowAmount,
      // no account yet (startEpoch)
      0
    );
    vcBasic.claim = abi.encode(agentData);
    pool.getRate(Account(0,0,0, true), vcBasic);
    uint256 rate = pool.getRate(Account(0,0,0, true), vcBasic);
    uint256 expectedRate = baseRate * rateArray[gCRED] / WAD;
    assertEq(rate, expectedRate);
  }
}

contract PoolIsOverLeveragedTest is PoolTestState {
    function testIsOverLeveragedBasic() public {
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertTrue(isApproved);
  }

  function testIsOverLeveragedLTVErrorBasic() public {
    // For the most basic path, the equity is 100%
    // This means the pool share of value is just total value less principal
    // With the current logic that means that whenever the agent value
    // is less than double the principle we should be over leveraged
    AgentData memory agentData = createAgentData(
      // collateral value => 2x the borrowAmount less dust
      (borrowAmount * 2) - 1000,
      gCredBasic,
      goodEDR,
      // principal = borrowAmount
      borrowAmount,
      // no account yet (startEpoch)
      0
    );
    vcBasic.claim = abi.encode(agentData);
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertFalse(isApproved);
  }

  function testIsOverLeveragedLTVErrorFuzz(uint256 borrowAmount, uint256 agentValue) public {
    borrowAmount = bound(borrowAmount, WAD, 1e22);
    // Even for very low values of agentValue there shouldn't be issues
    // If the agent value is less than 2x the borrow amount, we should be over leveraged
    agentValue = bound(agentValue, 0, (borrowAmount * 2) - 1000);
    AgentData memory agentData = createAgentData(
      // agentValue => 2x the borrowAmount less dust
      agentValue,
      gCredBasic,
      goodEDR,
      // principal = borrowAmount
      borrowAmount,
      // no account yet (startEpoch)
      0
    );
    vcBasic.claim = abi.encode(agentData);
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertFalse(isApproved);
  }

  function testIsOverLeveragedDTIErrorBasic() public {
    uint256 amount = WAD;
    uint256 principle = amount * 2;
    uint256 gCred = 80;
    AgentData memory agentData = createAgentData(
      // agentValue => 2x the borrowAmount
      principle,
      // good gcred score
      gCred,
      // bad EDR
      (rateArray[gCred] * EPOCHS_IN_DAY * amount / 2) / WAD,
      // principal = borrowAmount
      amount,
      // no account yet (startEpoch)
      0
    );
    vcBasic.claim = abi.encode(agentData);
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertFalse(isApproved);
  }

  function testIsOverLeveragedDTIErrorFuzz(uint256 borrowAmount, uint256 agentValue, uint256 badEDR) public {
    uint256 gCred = 80;

    borrowAmount = bound(borrowAmount, WAD, 1e22);
    agentValue = bound(agentValue, borrowAmount * 2, 1e30);
    uint256 badEDRUpper = ((rateArray[gCred] * EPOCHS_IN_DAY * borrowAmount) / WAD) -  DUST;
    badEDR = bound(badEDR, DUST, badEDRUpper);
    AgentData memory agentData = createAgentData(
      // agentValue => 2x the borrowAmount
      agentValue,
      // good gcred score
      gCred,
      // good EDR
      badEDR,
      // principal = borrowAmount
      borrowAmount,
      // no account yet (startEpoch)
      0
    );

    vcBasic.claim = abi.encode(agentData);
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertFalse(isApproved);
  }
}

contract PoolFeeTests is PoolTestState {
  function testHarvestToRamp() public {
    // Test setup
    uint256 amount = WAD;
    _setupRamp();
    _mintApproveIOU(amount, investor1, address(ramp));
    _stakeToRamp(amount, investor1);
    // Main test call
    pool.harvestToRamp();
    // The balance on the ramp is has been updated from the harvest
    assertEq(asset.balanceOf(address(ramp)), amount);
  }

  function testHarvestToRampNoDemand() public {
    _setupRamp();
    loadWFIL(WAD, address(ramp));
    uint256 exitDemand = ramp.totalIOUStaked();
    uint256 balanceBefore = asset.balanceOf(address(ramp));
    assertEq(balanceBefore, WAD, "Ramp should have WAD balance");
    assertEq(exitDemand, 0);
    // Main test call
    pool.harvestToRamp();
    assertEq(balanceBefore, asset.balanceOf(address(ramp)));
  }

  function testHarvestFees() public {
    uint256 amount = WAD;
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, borrowAmount));
    // Roll foward enough that all payment is interest
    // Once the math in Pay is fixed this should be posible to lower
    vm.roll(block.number + 1000000000);
    agentPay(agent, pool, issueGenericPayCred(agentID, amount));
    // Some of these numbers are inconsistent - we should calculate this value
    // instead of getting it from the contract once the calculations are stable
    uint256 feesCollected = pool.feesCollected();
    console.log("Fees Collected: %s", feesCollected);
    pool.harvestFees(feesCollected);
    assertEq(asset.balanceOf(treasury), feesCollected);
  }
}

contract Pool4626Tests is PoolTestState {

  function setUp () public override{
    super.setUp();
    _setupRamp();
  }

  function testPoolDepositAsset() public {
    uint256 amount = WAD;
    loadApproveWFIL(amount, investor1);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    vm.prank(investor1);
    pool.deposit(amount, investor1);
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, amount);
  }

  function testPoolDepositFil() public {
    uint256 amount = WAD;
    vm.deal(investor1, amount);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    pool.deposit{value: amount}(investor1);
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, amount);
  }

  function testPoolReceiveFil() public {
    uint256 amount = WAD;
    vm.deal(investor1, amount);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    vm.prank(investor1);
    address(pool).call{value: amount}("");
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, amount);
  }

  function testPoolFallbackFil() public {
    uint256 amount = WAD;
    vm.deal(investor1, amount);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    vm.prank(investor1);
    address(pool).call{value: amount}(abi.encodeWithSignature("fakeFunction(uint256, uint256)", 1, 2));
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, amount);
  }

  function testPoolMint() public {
    uint256 assets = WAD;
    uint256 shares = pool.convertToShares(WAD);
    loadApproveWFIL(assets, investor1);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    vm.prank(investor1);
    pool.mint(shares, investor1);
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, assets);
  }

  function testPoolWithdraw(uint256 amount) public {
    uint256 upperBound = pool.previewWithdraw(liquidStakingToken.balanceOf(address(investor1)));
    assertEq(upperBound, pool.maxWithdraw(investor1), "Expected withdraw should be equal to amount");
    amount = bound(amount, 1, upperBound);
    uint256 expectedWithdraw = pool.previewWithdraw(amount);
    uint256 balanceBeforeIOU = iou.balanceOf(address(ramp));
    uint256 balanceBeforeLST = liquidStakingToken.balanceOf(address(investor1));
    vm.prank(address(investor1));
    pool.withdraw(amount, investor1, investor1);
    uint256 balanceAfterIOU = iou.balanceOf(address(ramp));
    uint256 balanceAfterLST = liquidStakingToken.balanceOf(address(investor1));
    assertEq(balanceAfterIOU - balanceBeforeIOU, amount, "IOU balance should be updated");
    assertEq(balanceBeforeLST - balanceAfterLST, expectedWithdraw, "LST balance should be updated");

   }

  function testPoolRedeem(uint256 shares) public {
    uint256 assets = liquidStakingToken.balanceOf(address(investor1));
    uint256 upperBound = pool.convertToShares(assets);
    assertEq(upperBound, pool.maxRedeem(investor1), "Expected withdraw should be equal to amount");
    shares = bound(shares, 1, upperBound);
    uint256 expectedRedeem = pool.previewRedeem(shares);
    uint256 balanceBeforeIOU = iou.balanceOf(address(ramp));
    uint256 balanceBeforeLST = liquidStakingToken.balanceOf(address(investor1));
    vm.prank(address(investor1));
    pool.redeem(shares, investor1, investor1);
    uint256 balanceAfter = iou.balanceOf(address(ramp));
    uint256 balanceAfterIOU = iou.balanceOf(address(ramp));
    uint256 balanceAfterLST = liquidStakingToken.balanceOf(address(investor1));
    assertEq(balanceAfterIOU - balanceBeforeIOU, expectedRedeem, "IOU balance should be updated");
    assertEq(balanceBeforeLST - balanceAfterLST, shares, "LST balance should be updated");
  }

  function testMaxDeposit() public {
    // No limits on deposits
    assertEq(pool.maxDeposit(investor1), type(uint256).max);
  }

  function testMaxMint() public {
    // No limits on mints
    assertEq(pool.maxMint(investor1), type(uint256).max);
  }

  function testDepositZeroFail() public {
    vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
    vm.prank(address(investor1));
    pool.deposit(0, investor1);
  }

  function testSendZeroFail() public {
    vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
    vm.prank(address(investor1));
    pool.deposit(investor1);
  }

}


contract PoolAdminTests is PoolTestState {

  function testSetRamp() public {
    IOffRamp newRamp = IOffRamp(address(0x1));
    vm.prank(address(systemAdmin));
    pool.setRamp(newRamp);
    assertEq(address(pool.ramp()), address(newRamp));
  }

  function testJumpStartTotalBorrowed() public {
    uint256 amount = WAD;
    vm.prank(address(poolFactory));
    pool.jumpStartTotalBorrowed(amount);
    assertEq(pool.totalBorrowed(), amount);
  }

  function testJumpStartTotalBorrowedBadState() public {
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, WAD));
    vm.prank(address(poolFactory));
    vm.expectRevert(abi.encodeWithSelector(InvalidState.selector));
    pool.jumpStartTotalBorrowed(WAD);
  }

  function testSetMinimumLiquidity() public {
    uint256 amount = WAD;
    vm.prank(address(systemAdmin));
    pool.setMinimumLiquidity(amount);
    assertEq(pool.minimumLiquidity(), amount);
  }
  function testSetRateModule() public {
    IRateModule newRateModule = IRateModule(address(0x1));
    vm.prank(address(systemAdmin));
    pool.setRateModule(newRateModule);
    assertEq(address(pool.rateModule()), address(newRateModule));
  }

  function testDecommissionPool() public {
    IPool newPool = createAndFundPool(stakeAmount, investor1);
    assertEq(stakeAmount, asset.balanceOf(address(pool)));
    vm.prank(address(systemAdmin));
    pool.shutDown();
    assertTrue(pool.isShuttingDown(), "Pool should be shut down");
    vm.prank(address(poolFactory));
    // NOTE: can't decomission pool due to #361
    // pool.decommissionPool(newPool);

    // Need to make payments to test fee assertions

  }

}

contract PoolErrorBranches is PoolTestState {
  function testTotalBorrowableZero(uint256 borrowAmount) public {
    uint256 balance = asset.balanceOf(address(pool));
    uint256 minLiquidity = pool.getAbsMinLiquidity();
    borrowAmount = bound(borrowAmount, balance - minLiquidity , balance);
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, borrowAmount));
    assertEq(pool.totalBorrowableAssets(), 0, "Total borrowable should be zero");
  }

  function testLiquidAssetsOnShutdown() public {
    assertGt(pool.getLiquidAssets(), 0, "Liquid assets should be greater than zero before pool is shut down");
    vm.prank(address(systemAdmin));
    pool.shutDown();
    assertTrue(pool.isShuttingDown(), "Pool should be shut down");
    assertEq(pool.getLiquidAssets(), 0, "Liquid assets should be zero when pool is shutting down");
  }

  function testLiquidAssetsLessThanFees(uint256 borrowAmount, uint256 paymentAmount) public {
    uint256 paymentAmount = bound(paymentAmount, WAD, pool.totalBorrowableAssets());
    assertGt(pool.getLiquidAssets(), 0, "Liquid assets should be greater than zero before pool is shut down");
    // Our first borrow is based on the payment amount to generate fees
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, paymentAmount));
    // Roll foward enough that all payment is interest
    // Once the math in Pay is fixed this should be posible to lower
    vm.roll(block.number + 1000000000);
    agentPay(agent, pool, issueGenericPayCred(agentID, paymentAmount));
    uint256 feesCollected = pool.feesCollected();
    uint256 balance = asset.balanceOf(address(pool));
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, pool.totalBorrowableAssets()));
    assertEq(pool.getLiquidAssets(), 0, "Liquid assets should be zero when pool is shutting down");
  }

  function testMintZeroShares() public {
    vm.prank(address(investor1));
    vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
    pool.mint(0, investor1);
  }

}

// // a value we use to test approximation of the cursor according to a window start/close
// // TODO: investigate how to get this to 0 or 1
// uint256 constant EPOCH_CURSOR_ACCEPTANCE_DELTA = 1;

// contract PoolStakingTest is BaseTest {
//   using Credentials for VerifiableCredential;
//   IAgent agent;

//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   IPool pool;
//   IERC20 pool20;
//   IERC20 iou;

//   SignedCredential signedCred;

//   address investor1 = makeAddr("INVESTOR1");
//   address investor2 = makeAddr("INVESTOR2");
//   address investor3 = makeAddr("INVESTOR3");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));
//     iou = IERC20(address(pool.iou()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));
//   }

//   function testAsset() public {
//     ERC20 asset = pool.asset();
//     assertEq(asset.name(), "Wrapped Filecoin");
//     assertEq(asset.symbol(), "WFIL");
//     assertEq(asset.decimals(), 18);
//   }

//   function testPoolToken() public {
//     // NOTE: any reason not to just use pool20 here?
//     ERC20 poolToken = ERC20(address(pool.share()));
//     assertEq(poolToken.name(), poolName);
//     assertEq(poolToken.symbol(), poolSymbol);
//     assertEq(poolToken.decimals(), 18);
//   }

//   function testFailUnauthorizedPoolTokenMint() public {
//     address tester = makeAddr("TESTER");
//     // first check to make sure a pool can mint
//     vm.startPrank(address(pool));
//     pool.share().mint(tester, WAD);
//     vm.stopPrank();
//     assertEq(pool.share().balanceOf(tester), WAD);

//     tester = makeAddr("TESTER2");
//     vm.startPrank(tester);
//     pool.share().mint(tester, WAD);
//     vm.stopPrank();
//   }

//   function testSingleDepositWithdraw() public {
//     uint256 investor1UnderlyingAmount = WAD;

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     assertEq(wFIL.allowance(investor1, address(pool)), investor1UnderlyingAmount, "investor1 allowance");

//     uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

//     uint256 investor1ShareAmount = pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();
//     // Expect exchange rate to be 1:1 on initial deposit.
//     assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
//     assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
//     assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount, "Preview Depost = investor1 share amount");
//     assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");


//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
//     assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
//     assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");

//     assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount, "investor1 balance of underlying = investor1 pre deposit balance - investor1 underlying amount");

//     vm.prank(investor1);
//     pool.withdraw(investor1UnderlyingAmount, investor1, investor1);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0, "convertToAssets = 0");

//     assertEq(pool20.balanceOf(investor1), 0,  "Investor 1 balance of pool token = 0");
//     assertEq(pool.ramp().iouTokensStaked(investor1), investor1UnderlyingAmount, "investor1 IOU balance = investor1 underlying amount");

//   }

//   function testDepositFil() public {
//     uint256 investor1UnderlyingAmount = WAD;
//     vm.deal(investor1, investor1UnderlyingAmount);
//     vm.startPrank(investor1);
//     uint256 investor1ShareAmount = pool.deposit{value: investor1UnderlyingAmount}(investor1);
//     assertEq(wFIL.balanceOf(address(pool)), investor1UnderlyingAmount, "pool wfil balance = investor1 underlying amount");
//     // Expect exchange rate to be 1:1 on initial deposit.
//     assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
//     // assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
//     // assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");

//     // assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
//     // assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
//     // assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");
//   }

//   function testSendFilIntoPool() public {
//     uint256 investor1UnderlyingAmount = WAD;
//     vm.deal(investor1, investor1UnderlyingAmount);
//     vm.startPrank(investor1);
//     address(pool).call{value: investor1UnderlyingAmount}("");
//     assertEq(wFIL.balanceOf(address(pool)), investor1UnderlyingAmount, "pool wfil balance = investor1 underlying amount");
//     uint256 investor1ShareAmount = pool20.balanceOf(investor1);
//     // Expect exchange rate to be 1:1 on initial deposit.
//     assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
//     assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
//     assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");

//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
//     assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
//     assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");
//   }

//   function testSingleMintRedeem() public {
//     uint256 investor1ShareAmount = WAD;

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1ShareAmount);
//     assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

//     uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

//     uint256 investor1UnderlyingAmount = pool.mint(investor1ShareAmount, investor1);
//     vm.stopPrank();
//     // Expect exchange rate to be 1:1 on initial mint.
//     assertEq(investor1ShareAmount, investor1UnderlyingAmount);
//     assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
//     assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount);
//     assertEq(pool.totalAssets(), investor1UnderlyingAmount);

//     assertEq(pool20.totalSupply(), investor1ShareAmount);
//     assertEq(pool20.balanceOf(investor1), investor1UnderlyingAmount);
//     assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

//     vm.prank(investor1);
//     pool.redeem(investor1ShareAmount, investor1, investor1);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0);

//     assertEq(pool20.balanceOf(investor1), 0);
//     assertEq(pool.ramp().iouTokensStaked(investor1), investor1UnderlyingAmount);

//   }

//   function testFailDepositWithNotEnoughApproval() public {
//         wFIL.deposit{value: 0.5e18}();
//         wFIL.approve(address(pool), 0.5e18);
//         assertEq(wFIL.allowance(address(this), address(pool)), 0.5e18);

//         pool.deposit(WAD, address(this));
//     }

//   function testMintForReceiver() public {
//     uint256 investor1ShareAmount = WAD;

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1ShareAmount);
//     assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

//     uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

//     uint256 investor1UnderlyingAmount = pool.mint(investor1ShareAmount, investor2);
//     vm.stopPrank();
//     // Expect exchange rate to be 1:1 on initial mint.
//     assertEq(investor1ShareAmount, investor1UnderlyingAmount);
//     assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
//     assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor1UnderlyingAmount);
//     assertEq(pool.totalAssets(), investor1UnderlyingAmount);

//     assertEq(pool20.totalSupply(), investor1ShareAmount);
//     assertEq(pool20.balanceOf(investor2), investor1UnderlyingAmount);
//     assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);
//   }

//   function testDepositForReceiver() public {
//     uint256 investor1UnderlyingAmount = WAD;
//     uint256 investor1ShareAmount = pool.previewDeposit(investor1UnderlyingAmount);

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1ShareAmount);
//     assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

//     uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

//     pool.deposit(investor1UnderlyingAmount, investor2);
//     vm.stopPrank();
//     // Expect exchange rate to be 1:1 on initial mint.
//     assertEq(investor1ShareAmount, investor1UnderlyingAmount);
//     assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
//     assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor1UnderlyingAmount);
//     assertEq(pool.totalAssets(), investor1UnderlyingAmount);

//     assertEq(pool20.totalSupply(), investor1ShareAmount);
//     assertEq(pool20.balanceOf(investor2), investor1UnderlyingAmount);
//     assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);
//   }

//     function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
//         wFIL.deposit{value: 0.5e18}();
//         wFIL.approve(address(pool), 0.5e18);

//         pool.deposit(0.5e18, address(this));

//         pool.withdraw(WAD, address(this), address(this));
//     }

//     function testFailRedeemWithNotEnoughShareAmount() public {
//         wFIL.deposit{value: 0.5e18}();
//         wFIL.approve(address(pool), 0.5e18);

//         pool.deposit(0.5e18, address(this));

//         pool.redeem(WAD, address(this), address(this));
//     }

//     function testFailWithdrawWithNoUnderlyingAmount() public {
//         pool.withdraw(WAD, address(this), address(this));
//     }

//     function testFailRedeemWithNoShareAmount() public {
//         pool.redeem(WAD, address(this), address(this));
//     }

//     function testFailDepositWithNoApproval() public {
//         pool.deposit(WAD, address(this));
//     }

//     function testFailMintWithNoApproval() public {
//       vm.prank(investor1);
//       pool.mint(WAD, address(this));
//       vm.stopPrank();
//     }

//     function testFailDepositZero() public {
//         pool.deposit(0, address(this));
//     }

//     function testMintZero() public {
//       vm.prank(investor1);
//       vm.expectRevert("Pool: cannot mint 0 shares");
//       pool.mint(0, address(this));
//       vm.stopPrank();
//     }

//     function testFailRedeemZero() public {
//         pool.redeem(0, address(this), address(this));
//     }

//     function testWithdrawZero() public {
//         pool.withdraw(0, address(this), address(this));

//         assertEq(pool20.balanceOf(address(this)), 0);
//         assertEq(pool.convertToAssets(pool20.balanceOf(address(this))), 0);
//         assertEq(pool20.totalSupply(), 0);
//         assertEq(pool.totalAssets(), 0);
//     }
// }

// contract PoolBorrowingTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;

//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 0.5e18;
//   uint256 investor1UnderlyingAmount = WAD;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));
//   }

//   function testBorrow() public {
//     vm.startPrank(investor1);

//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();
//     uint256 prevMinerBal = wFIL.balanceOf(address(agent));

//     uint256 powerAmtStake = WAD;
//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), issueGenericSC(address(agent)));
//     vm.stopPrank();

//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);
//     uint256 startEpoch = block.number;
//     uint256 postMinerBal = wFIL.balanceOf(address(agent));

//     vm.stopPrank();

//     assertEq(postMinerBal - prevMinerBal, borrowAmount);

//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, startEpoch);
//     assertGt(account.pmtPerEpoch(), 0);

//     uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
//     uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));
//     assertEq(poolPowTokenBal, powerAmtStake);
//     assertEq(agentPowTokenBal, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - powerAmtStake);
//     assertEq(poolPowTokenBal + agentPowTokenBal, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//   }

//   function testMultiBorrowNoDeficit() public {

//   }

//   function testBorrowInsufficientLiquidity() public {
//     vm.startPrank(investor1);

//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();
//     uint256 prevMinerBal = wFIL.balanceOf(address(agent));

//     uint256 powerAmtStake = 2e18;
//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();

//     uint256 startEpoch = block.number;
//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake / 2);
//     SignedCredential memory sc = issueGenericSC(address(agent));

//     vm.startPrank(address(agent));
//     powerToken.approve(address(pool), powerAmtStake);
//     try pool.borrow(investor1UnderlyingAmount, sc, (powerAmtStake / 2)) {
//       assertTrue(false, "should not be able to borrow w sufficient liquidity");
//     } catch (bytes memory b) {
//       assertEq(errorSelector(b), InsufficientLiquidity.selector, "should be InsufficientLiquidity error");
//     }
//     vm.stopPrank();
//   }

//   // tests a deficit < borrow amt
//   function testBorrowDeficitWAdditionalProceeds() public {}

//   // tests a deficit > borrow amt
//   function testBorrowDeficitNoProceeds() public {}


//   function testTotalBorrowable() public {

//     vm.startPrank(investor1);

//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();
//     uint256 prevMinerBal = wFIL.balanceOf(address(agent));

//     uint256 powerAmtStake = WAD;
//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();

//     uint256 startEpoch = block.number;
//     uint256 postMinerBal = wFIL.balanceOf(address(agent));
//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);


//     uint256 totalBorrowable = pool.totalBorrowableAssets();
//     uint256 totalBorrowed = pool.totalBorrowed();
//     assertEq(totalBorrowed, borrowAmount);
//     assertEq(totalBorrowable, investor1UnderlyingAmount - borrowAmount);
//   }
// }

// contract PoolExitingTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;

//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   // this isn't ideal but it also prepares us better to separate the pool token from the pool
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 0.5e18;
//   uint256 investor1UnderlyingAmount = WAD;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   uint256 borrowBlock;

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     uint256 powerAmtStake = WAD;
//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();

//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);
//     borrowBlock = block.number;
//   }

//   function testFullExit() public {
//     vm.startPrank(minerOwner);
//     agent.exit(pool.id(), borrowAmount, issueGenericSC(address(agent)));
//     vm.stopPrank();

//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, 0);
//     assertEq(account.powerTokensStaked, 0);
//     assertEq(account.startEpoch, 0);
//     assertEq(account.pmtPerEpoch(), 0);
//     assertEq(account.epochsPaid, 0);
//     assertEq(pool.totalBorrowed(), 0);
//   }

//   function testPartialExitWithinCurrentWindow() public {
//     uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
//     vm.startPrank(minerOwner);
//     agent.exit(pool.id(), borrowAmount / 2, issueGenericSC(address(agent)));
//     vm.stopPrank();

//     uint256 poolPowTokenBalAfter = IERC20(address(powerToken)).balanceOf(address(pool));

//     Account memory accountAfter = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(accountAfter.totalBorrowed, borrowAmount / 2);
//     assertEq(accountAfter.powerTokensStaked, poolPowTokenBal - poolPowTokenBalAfter);
//     assertEq(accountAfter.startEpoch, borrowBlock);
//     assertGt(accountAfter.pmtPerEpoch(), 0);
//     // exiting goes towards principal and does not credit partial payment on account
//     assertEq(pool.totalBorrowed(), borrowAmount / 2);
//   }
// }

// contract PoolMakePaymentTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;
//   IAgentPolice police;


//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   // this isn't ideal but it also prepares us better to separate the pool token from the pool
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 0.5e18;
//   uint256 powerAmtStake = WAD;
//   uint256 investor1UnderlyingAmount = WAD;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   uint256 borrowBlock;

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();
//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);
//     borrowBlock = block.number;

//     police = GetRoute.agentPolice(router);
//   }

//   function testFullPayment() public {

//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     // This should be equal to the window start, not necesarily 0 - same is true of all instances
//     assertEq(account.epochsPaid, police.windowInfo().start, "Account should not have epochsPaid > window.start before making a payment");
//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());

//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), minPaymentToCloseWindow);
//     pool.makePayment(address(agent), minPaymentToCloseWindow);
//     vm.stopPrank();
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, borrowBlock);
//     assertEq(pool.totalBorrowed(), borrowAmount);
//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
//     assertApproxEqAbs(
//       account.epochsPaid,
//       nextPaymentWindowClose,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account should have paid up to the end of the next payment window"
//     );
//     assertTrue(account.epochsPaid >= nextPaymentWindowClose);
//   }

//   function testPartialPmtWithinCurrentWindow() public {
//     Window memory window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
//     uint256 pmtPerEpoch = account.pmtPerEpoch();
//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());
//     // Round up to ensure we don't pay less than the minimum
//     uint256 partialPayment = minPaymentToCloseWindow / 2 + (minPaymentToCloseWindow % 2);
//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), partialPayment);
//     pool.makePayment(address(agent), partialPayment);
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount, "Account total borrowed should not change");
//     assertEq(account.powerTokensStaked, powerAmtStake, "Account power tokens staked should not change");
//     assertEq(account.startEpoch, borrowBlock, "Account start epoch should not change");
//     assertEq(account.pmtPerEpoch(), pmtPerEpoch, "Account payment per epoch should not change");
//     assertEq(pool.totalBorrowed(), borrowAmount, "Pool total borrowed should not change");

//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     assertApproxEqAbs(
//       account.epochsPaid,
//       (window.start) + window.length / 2,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account epochsPaid shold be half the window length"
//     );
//     assertTrue(account.epochsPaid >= window.start +  (window.length / 2) );
//   }

//   function testForwardPayment() public {
//     Window memory window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
//     uint256 pmtPerEpoch = account.pmtPerEpoch();
//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());
//     uint256 forwardPayment = minPaymentToCloseWindow * 2;

//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), forwardPayment);
//     pool.makePayment(address(agent), forwardPayment);
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, borrowBlock);
//     assertEq(account.pmtPerEpoch(), pmtPerEpoch);
//     assertEq(pool.totalBorrowed(), borrowAmount);
//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     assertApproxEqAbs(
//       account.epochsPaid,
//       window.deadline + window.length,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account epochsPaid should be 2 nextPmtWindowDeadlines forward"
//     );

//     assertTrue(account.epochsPaid >= window.deadline + window.length);
//   }

//   function testMultiPartialPaymentsToPmtPerPeriod() public {
//     Window memory window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
//     uint256 pmtPerEpoch = account.pmtPerEpoch();
//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());

//     uint256 partialPayment = minPaymentToCloseWindow / 2;
//     vm.stopPrank();

//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), partialPayment);
//     pool.makePayment(address(agent), partialPayment);

//     // roll forward in time for shits and gigs
//     vm.roll(block.number + 1);
//     window = police.windowInfo();
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     partialPayment = account.getMinPmtForWindowClose(window, router, pool.implementation());
//     wFIL.approve(address(pool), partialPayment);
//     pool.makePayment(address(agent), partialPayment);

//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, borrowBlock);
//     assertEq(account.pmtPerEpoch(), pmtPerEpoch);
//     assertEq(pool.totalBorrowed(), borrowAmount);
//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     assertApproxEqAbs(
//       account.epochsPaid,
//       window.deadline,
//       0,
//       "Account epochsPaid should be the nextPmtWindowDeadline"
//     );

//     assertTrue(account.epochsPaid >= window.deadline);
//   }

//   function testLatePaymentToCloseCurrentWindow() public {
//     Window memory window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(
//       account.epochsPaid,
//       window.start,
//       "Account should not have epochsPaid > window.start before making a payment"
//     );

//     // fast forward a window deadlines
//     vm.roll(block.number + window.length);

//     window = police.windowInfo();

//     uint256 pmtPerEpoch = account.pmtPerEpoch();
//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());

//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), minPaymentToCloseWindow);

//     pool.makePayment(address(agent), minPaymentToCloseWindow);
//     vm.stopPrank();

//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, borrowBlock);
//     assertEq(account.pmtPerEpoch(), pmtPerEpoch);
//     assertEq(pool.totalBorrowed(), borrowAmount);

//     assertApproxEqAbs(
//       account.epochsPaid,
//       window.deadline,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account epochsPaid should be the end of the current window."
//     );

//     assertTrue(account.epochsPaid >= window.deadline);
//   }

//   function testLatePaymentToGetCurrent() public {
//     vm.startPrank(address(agent));
//     Window memory window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
//     assertEq(
//       account.epochsPaid,
//       window.start,
//       "Account should not have epochsPaid > window.start before making a payment"
//     );
//     // fast forward a window period
//     vm.roll(block.number + window.length);

//     window = police.windowInfo();

//     uint256 pmtPerEpoch = account.pmtPerEpoch();
//     uint256 minPaymentToGetCurrent = account.getMinPmtForWindowStart(window, router, pool.implementation());
//     wFIL.approve(address(pool), minPaymentToGetCurrent);

//     pool.makePayment(address(agent), minPaymentToGetCurrent);
//     vm.stopPrank();

//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(account.startEpoch, borrowBlock);
//     assertEq(account.pmtPerEpoch(), pmtPerEpoch);
//     assertEq(pool.totalBorrowed(), borrowAmount);

//     assertApproxEqAbs(
//       account.epochsPaid,
//       window.start,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account epochsPaid should be the current window start"
//     );
//     assertTrue(account.epochsPaid >= window.start);
//   }
// }

// contract PoolPenaltiesTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;
//   IAgentPolice police;


//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   // this isn't ideal but it also prepares us better to separate the pool token from the pool
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 0.5e18;
//   uint256 powerAmtStake = WAD;
//   uint256 investor1UnderlyingAmount = WAD;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   uint256 borrowBlock;

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     borrowBlock = block.number;

//     vm.stopPrank();

//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);

//     police = GetRoute.agentPolice(router);
//   }

//   function testAccruePenaltyEpochs() public {
//     vm.startPrank(_agentOperator(agent));
//     // fast forward 2 window periods
//     Window memory window = police.windowInfo();
//     vm.roll(block.number + window.length*2);
//     window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     // penalty epochs here should be 1 window length, since we fast forwarded 2 windows
//     uint256 penaltyEpochs = account.getPenaltyEpochs(window);
//     assertEq(penaltyEpochs, window.length, "Account should have 1 windows length of penalty epochs");
//   }

//   /// In this example, we fast forward 2 windows, so the Agent owes for 3 total windows
//   /// then we make a payment to close the window
//   /// since a penalty is paid for 1 window, the pmtPerPeriod * 3 < amount paid
//   function testMakePaymentWithPenaltyToCloseWindow() public {
//     Window memory window = police.windowInfo();
//     vm.roll(block.number + window.length*2);
//     window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());
//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), minPaymentToCloseWindow);
//     pool.makePayment(address(agent), minPaymentToCloseWindow);
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(pool.totalBorrowed(), borrowAmount);
//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
//     assertApproxEqAbs(
//       account.epochsPaid,
//       nextPaymentWindowClose,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account should have paid up to the end of the next payment window"
//     );
//     assertTrue(account.epochsPaid >= nextPaymentWindowClose);
//     assertTrue(minPaymentToCloseWindow >= account.pmtPerPeriod(router) * 3, "Min payment to close window should be greater than 3 period payments");
//     // NOTE: this condition isn't always true, if the penalties are large enough. it is true in our test environment
//     assertTrue(minPaymentToCloseWindow < account.pmtPerPeriod(router) * 4, "Min payment to close window should be less than than 4 period payments");
//     vm.stopPrank();
//   }

//   function testMakePaymentWithPenaltyToCurrent() public {
//     Window memory window = police.windowInfo();
//     vm.roll(block.number + window.length*2);
//     window = police.windowInfo();
//     Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     uint256 minPayment = account.getMinPmtForWindowStart(police.windowInfo(), router, pool.implementation());

//     vm.startPrank(address(agent));
//     wFIL.approve(address(pool), minPayment);
//     pool.makePayment(address(agent), minPayment);
//     account = AccountHelpers.getAccount(router, address(agent), pool.id());

//     assertEq(account.totalBorrowed, borrowAmount);
//     assertEq(account.powerTokensStaked, powerAmtStake);
//     assertEq(pool.totalBorrowed(), borrowAmount);
//     uint256 windowStart = police.windowInfo().start;
//     // since we paid the full amount, the last payment epoch should be the end of the next payment window
//     assertApproxEqAbs(
//       account.epochsPaid,
//       windowStart,
//       EPOCH_CURSOR_ACCEPTANCE_DELTA,
//       "Account should have paid up to the end of the next payment window"
//     );
//     assertTrue(account.epochsPaid >= windowStart);
//     assertTrue(minPayment >= account.pmtPerPeriod(router) * 2, "Min payment to close window should be greater than 3 period payments");
//     // NOTE: this condition isn't always true, if the penalties are large enough. it is true in our test environment
//     assertTrue(minPayment < account.pmtPerPeriod(router) * 3, "Min payment to close window should be less than than 4 period payments");
//   }

//   function testBorrowInPenalty() public {
//     vm.startPrank(_agentOperator(agent));
//     // fast forward 2 window periods
//     Window memory window = police.windowInfo();
//     vm.roll(block.number + window.length*2);
//     window = police.windowInfo();

//     SignedCredential memory sc = issueGenericSC(address(agent));
//     vm.stopPrank();

//     vm.startPrank(address(agent));
//     powerToken.approve(address(pool), powerAmtStake);
//     try pool.borrow(borrowAmount, sc, powerAmtStake) {
//       assertTrue(false, "Should not be able to borrow in penalty");
//     } catch (bytes memory err) {
//       assertEq(errorSelector(err), Unauthorized.selector);
//     }

//     vm.stopPrank();
//   }
// }

// contract TreasuryFeesTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;
//   IAgentPolice police;


//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   // this isn't ideal but it also prepares us better to separate the pool token from the pool
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 0.5e18;
//   uint256 powerAmtStake = WAD;
//   uint256 investor1UnderlyingAmount = WAD;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   uint256 borrowBlock;

//   function setUp() public {
//     poolFactory = GetRoute.poolFactory(router);
//     powerToken = GetRoute.powerToken(router);
//     treasury = GetRoute.treasury(router);
//     police = GetRoute.agentPolice(router);

//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();
//     borrowBlock = block.number;
//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);
//   }

//   function testTreasuryFees() public {
//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), WAD);
//     pool.makePayment(address(agent), WAD);
//     vm.stopPrank();
//     uint256 treasuryBalance = wFIL.balanceOf(treasury);
//     assertEq(treasuryBalance, (WAD * .10), "Treasury should have received 10% fees");
//   }
// }

// contract PoolUpgradeTest is BaseTest {
//   using AccountHelpers for Account;
//   using Credentials for VerifiableCredential;

//   IAgent agent;
//   IAgentPolice police;

//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   // this isn't ideal but it also prepares us better to separate the pool token from the pool
//   IPool pool;
//   IERC20 pool20;

//   SignedCredential signedCred;

//   uint256 borrowAmount = 5e18;
//   uint256 powerAmtStake = WAD;
//   uint256 investor1UnderlyingAmount = 10e18;
//   address investor1 = makeAddr("INVESTOR1");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   function setUp() public {
//     poolFactory = GetRoute.poolFactory(router);
//     powerToken = GetRoute.powerToken(router);
//     treasury = GetRoute.treasury(router);
//     police = GetRoute.agentPolice(router);
//     pool = createPool(
//       poolName,
//       poolSymbol,
//       poolOperator,
//       20e18
//     );
//     pool20 = IERC20(address(pool.share()));

//     vm.deal(investor1, 100e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 100e18}();
//     require(wFIL.balanceOf(investor1) == 100e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));

//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     vm.startPrank(_agentOperator(agent));
//     agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//     vm.stopPrank();

//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);
//   }

//   function testSetRamp() public {
//     address newRamp = makeAddr("NEW_RAMP");
//     vm.prank(poolOperator);
//     pool.setRamp(IOffRamp(newRamp));
//     assertEq(address(pool.ramp()), newRamp, "Ramp should be set");
//   }

//   function testTransferOwner() public {
//     IAuth poolAuth = IAuth(address(pool));
//     address owner = makeAddr("OWNER");
//     vm.prank(poolOperator);
//     poolAuth.transferOwnership(owner);
//     assertEq(poolAuth.pendingOwner(), owner);
//     vm.prank(owner);
//     poolAuth.acceptOwnership();
//     assertEq(poolAuth.owner(), owner);
//   }

//   function testTransferOperator() public {
//     IAuth poolAuth = IAuth(address(pool));
//     address operator = makeAddr("OPERATOR");
//     vm.prank(poolOperator);
//     poolAuth.transferOperator(operator);
//     assertEq(poolAuth.pendingOperator(), operator);
//     vm.prank(operator);
//     poolAuth.acceptOperator();
//     assertEq(poolAuth.operator(), operator);
//   }

//   function testShutDown() public {
//     assertTrue(!pool.isShuttingDown(), "Pool should not be shut down");
//     vm.prank(poolOperator);
//     pool.shutDown();
//     assertTrue(pool.isShuttingDown(), "Pool should be shut down");
//   }

//   function testSetImplementation() public {
//     address newImplementation = makeAddr("NEW_IMPLEMENTATION");
//     // expect this call to revert because the implementation is not approved
//     vm.expectRevert("Pool: Invalid implementation");
//     vm.prank(poolOperator);
//     pool.setImplementation(IPoolImplementation(newImplementation));

//     // approve the Implementation
//     vm.prank(IAuth(address(poolFactory)).owner());
//     poolFactory.approveImplementation(newImplementation);

//     // now this should work
//     vm.prank(poolOperator);
//     pool.setImplementation(IPoolImplementation(newImplementation));
//     assertEq(address(pool.implementation()), newImplementation, "Implementaton should be set");
//   }

//   function testSetMinimumLiquidity() public {
//     uint256 newMinLiq = 1.3e18;
//     vm.prank(poolOperator);
//     pool.setMinimumLiquidity(newMinLiq);
//     assertEq(pool.minimumLiquidity(), newMinLiq, "Minimum liquidity should be set");
//   }

//   function testUpgradePool() public {
//     // at this point, the pool has 1 staker, and 1 borrower

//     // get stats before upgrade
//     uint256 investorPoolShares = pool.share().balanceOf(investor1);
//     uint256 totalBorrowed = pool.totalBorrowed();
//     uint256 agentBorrowed = pool.getAgentBorrowed(agent.id());
//     uint256 powerTokenBalance = powerToken.balanceOf(address(pool));

//     // first shut down the pool
//     vm.prank(poolOperator);
//     pool.shutDown();
//     // then upgrade it
//     vm.startPrank(IAuth(address(pool)).owner());
//     pool = poolFactory.upgradePool(pool.id());
//     vm.stopPrank();

//     uint256 investorPoolSharesNew = pool.share().balanceOf(investor1);
//     uint256 totalBorrowedNew = pool.totalBorrowed();
//     uint256 agentBorrowedNew = pool.getAgentBorrowed(agent.id());

//     assertEq(investorPoolSharesNew, investorPoolShares);
//     assertEq(totalBorrowedNew, totalBorrowed);
//     assertEq(agentBorrowedNew, agentBorrowed);
//     assertEq(powerToken.balanceOf(address(pool)), powerTokenBalance);

//     // now attempt to deposit and borrow again
//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, address(powerToken), powerAmtStake);

//     // investorPoolSharesNew = pool.share().balanceOf(investor1);
//     // totalBorrowedNew = pool.totalBorrowed();
//     // agentBorrowedNew = pool.getAgentBorrowed(agent.id());

//     // assertGt(investorPoolSharesNew, investorPoolShares);
//     // assertGt(totalBorrowedNew, totalBorrowed);
//     // assertGt(agentBorrowedNew, agentBorrowed);
//   }
// }
