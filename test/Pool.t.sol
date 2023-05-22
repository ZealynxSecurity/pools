// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IInfinityPool} from "src/Types/Interfaces/IInfinityPool.sol";

import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {NewCredParser} from "test/helpers/NewCredParser.sol";
import {NewCredentials, NewAgentData} from "test/helpers/NewCredentials.sol";
contract PoolTestState is BaseTest {

  error InvalidState();

  using Credentials for VerifiableCredential;

  IPool pool;
  IPoolRegistry poolRegistry;
  uint256 borrowAmount = WAD;
  uint256 stakeAmount = 1000e18;
  uint256 expectedRateBasic = 15e16;
  uint256 goodEDR = .01e18;
  address investor1 = makeAddr("INVESTOR_1");
  address minerOwner = makeAddr("MINER_OWNER");
  uint256 gCredBasic;
  SignedCredential borrowCredBasic;
  VerifiableCredential vcBasic;
  IAgent agent;
  uint64 miner;
  IPoolToken public liquidStakingToken;
  IERC20 public asset;
  uint256 agentID;
  uint256 poolID;
  IOffRamp ramp;
  IPoolToken iou;
  address newCredParser;

  function setUp() public virtual {
    (pool, agent, miner, borrowCredBasic, vcBasic, gCredBasic) = PoolBasicSetup(
      stakeAmount,
      borrowAmount,
      investor1,
      minerOwner
    );
    poolRegistry = GetRoute.poolRegistry(router);
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

  function _updateCredParser() internal {
    newCredParser = address(new NewCredParser());
    vm.startPrank(systemAdmin);
    Router(router).pushRoute(ROUTE_CRED_PARSER, newCredParser);
    pool.rateModule().updateCredParser();
    assertEq(pool.rateModule().credParser(), newCredParser);
    vm.stopPrank();
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
    vm.startPrank(staker);
    // Finally, we can stake & harvest after setup
    ramp.stake(amount);
  }

  function _generateFees(uint256 paymentAmt, uint256 initialBorrow) internal {
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, initialBorrow));
    vm.roll(block.number + GetRoute.agentPolice(router).defaultWindow() - 1);
    agentPay(agent, pool, issueGenericPayCred(agentID, paymentAmt));
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

  function testCreatePool() public {
    IPoolRegistry poolRegistry = GetRoute.poolRegistry(router);
    PoolToken liquidStakingToken = new PoolToken(systemAdmin);
    uint256 id = poolRegistry.allPoolsLength();
    address rateModule = address(new RateModule(systemAdmin, router, rateArray, levels));
    pool = IPool(new InfinityPool(
      systemAdmin,
      router,
      address(wFIL),
      //
      rateModule,
      // no min liquidity for test pool
      address(liquidStakingToken),
      address(new PreStake(systemAdmin, IWFIL(address(wFIL)), IPoolToken(address(liquidStakingToken)))),
      0,
      id
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
    poolRegistry.attachPool(pool);
    assertEq(poolRegistry.allPoolsLength(), id + 1, "pool not added to allPools");
    vm.stopPrank();
  }
}

contract PoolDrainTest is PoolTestState {
  function testDrainPool() public {
    uint256 amount = 100e18;
    loadApproveWFIL(amount, investor1);
    vm.prank(investor1);
    pool.deposit(amount, investor1);

    address prankster = makeAddr("PRANKSTER");

    uint256 totalBorrowable = pool.totalBorrowableAssets();
    SignedCredential memory sc = issueGenericBorrowCred(0, totalBorrowable);

    // Confirm that the pool has the FIL
    uint256 preDrainPoolBal = wFIL.balanceOf(address(pool));
    assertGt(preDrainPoolBal, 0, "Pool should have FIL");
    assertEq(wFIL.balanceOf(prankster), 0, "prankster should not have fil");

    vm.startPrank(prankster);
    vm.expectRevert(Unauthorized.selector);
    pool.borrow(sc.vc);
    vm.stopPrank();

    assertEq(wFIL.balanceOf(address(pool)), preDrainPoolBal, "Pool should not have been drained");
    assertEq(wFIL.balanceOf(prankster), 0, "Prankster should not have received money");
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
  using FixedPointMathLib for uint256;

  function testGetRateBasic() public {
    uint256 rate = pool.getRate(vcBasic);
    uint256 expectedRate = DEFAULT_BASE_RATE.mulWadUp(rateArray[gCredBasic - pool.rateModule().minGCRED()]);
    assertEq(rate, expectedRate);
  }

  function testGetRateFuzz(uint256 gCRED) public {
    gCRED = bound(gCRED, 40, 100);
    AgentData memory agentData = createAgentData(
      // collateral value => 2x the borrowAmount
      borrowAmount * 2,
      // good gcred score
      gCRED,
      // good EDR
      goodEDR,
      // principal = borrowAmount
      borrowAmount
    );
    vcBasic.claim = abi.encode(agentData);
    uint256 rate = pool.getRate(vcBasic);
    uint256 expectedRate = DEFAULT_BASE_RATE.mulWadUp(rateArray[gCRED - pool.rateModule().minGCRED()]);
    assertEq(rate, expectedRate);
  }
}

contract PoolIsOverLeveragedTest is PoolTestState {

  using FixedPointMathLib for uint256;

  function testIsApprovedSuccess() public {
    bool isApproved = pool.isApproved(createAccount(borrowAmount), vcBasic);
    assertTrue(isApproved, "Should be approved");
  }

  function testIsApprovedOverLTV(uint256 principal, uint256 collateralValue) public {
    principal = bound(principal, WAD, MAX_FIL - DUST);
    // Even for very low values of agentValue there shouldn't be issues
    // If the agent value is less than 2x the borrow amount, we should be over leveraged
    collateralValue = bound(collateralValue, DUST, principal - DUST);

    IRateModule rateModule = IRateModule(pool.rateModule());

    AgentData memory agentData = createAgentData(
      // collateralValue => 2x the borrowAmount less dust
      collateralValue,
      GCRED,
      // enormous EDR to ensure we are not over DTI
      MAX_FIL,
      // principal = borrowAmount
      principal
    );
    // overwrite agent value to avoid DTE errors
    agentData.agentValue = principal * 3;
    vcBasic.claim = abi.encode(agentData);

    Account memory account = createAccount(principal);

    assertFalse(pool.isApproved(account, vcBasic), "Should not be approved");
    // ensure this test failed because of the right check
    assertTrue(
      rateModule.computeLTV(principal, collateralValue) > rateModule.maxLTV(), "Should be over LTV"
    );
    assertTrue(
      rateModule.computeDTI(
        agentData.expectedDailyRewards,
        pool.getRate(vcBasic),
        principal,
        principal
      ) < rateModule.maxDTI(), "Should be under DTI"
    );
    assertTrue(
      rateModule.computeDTE(principal, agentData.agentValue) < rateModule.maxDTE(), "Should be under DTE"
    );
  }

  function testDTECalcNoFuzz() public {
    uint256 agentTotalValue = 1000000000000010000;
    uint256 principal = 1000000000000000000;

    // this DTE is known to be way over 100%
    uint256 dte = pool.rateModule().computeDTE(principal, agentTotalValue);
    assertGt(dte, 1e18, "DTE should be around 100%");

    // this DTE is known to be 50%
    agentTotalValue = 3e18;
    principal = 1e18;
    dte = pool.rateModule().computeDTE(principal, agentTotalValue);
    assertEq(dte, 5e17, "DTE should be 50%");
  }

  function testIsApprovedOverDTI(
    uint256 principal,
    uint256 collateralValue,
    uint256 badEDR
  ) public {
    principal = bound(principal, WAD, 1e22);
    collateralValue = bound(collateralValue, principal * 2, 1e30);

    IRateModule rateModule = IRateModule(pool.rateModule());

    uint256 badEDRUpper =
      _getAdjustedRate(GCRED)
      .mulWadUp(principal)
      .mulWadUp(EPOCHS_IN_DAY)
      .divWadDown(rateModule.maxDTE());

    badEDR = bound(badEDR, DUST, badEDRUpper - DUST);

    AgentData memory agentData = createAgentData(
      collateralValue,
      GCRED,
      // edr < expectedDailyPayment
      badEDR,
      principal
    );

    Account memory account = createAccount(principal);

    vcBasic.claim = abi.encode(agentData);
    assertFalse(pool.isApproved(account, vcBasic));
    // ensure this test failed because of the right check
    assertTrue(
      rateModule.computeLTV(principal, collateralValue) < rateModule.maxLTV(), "Should be under LTV"
    );
    assertTrue(
      rateModule.computeDTI(
        agentData.expectedDailyRewards,
        pool.getRate(vcBasic),
        principal,
        principal
      ) > rateModule.maxDTI(), "Should be over DTI"
    );
    assertTrue(
      rateModule.computeDTE(principal, agentData.agentValue) < rateModule.maxDTE(), "Should be under DTE"
    );
  }

  function testKnownLTV() public {
    uint256 principal = 1e18;
    uint256 collateralValue = 2e18;
    uint256 ltv = pool.rateModule().computeLTV(principal, collateralValue);
    assertEq(ltv, 5e17, "LTV should be 50%");
  }

  function testIsApprovedOverDTE(
    uint256 principal,
    uint256 agentValue
  ) public {
    IRateModule rateModule = IRateModule(pool.rateModule());
    uint256 maxDTE = rateModule.maxDTE();
    principal = bound(principal, DUST, MAX_FIL);
    agentValue = bound(agentValue, 0, principal.divWadDown(maxDTE));

    AgentData memory agentData = createAgentData(
      // great collateral value so we dont have LTV error
      MAX_FIL,
      GCRED,
      // great EDR so we dont have DTI error
      MAX_FIL,
      principal
    );

    Account memory account = createAccount(principal);
    agentData.agentValue = agentValue;
    vcBasic.claim = abi.encode(agentData);
    assertFalse(pool.isApproved(account, vcBasic), "Should be false");
    // ensure this test failed because of the right check
    assertTrue(
      rateModule.computeLTV(principal, agentData.collateralValue) < rateModule.maxLTV(), "Should be under LTV"
    );
    assertTrue(
      rateModule.computeDTI(
        agentData.expectedDailyRewards,
        pool.getRate(vcBasic),
        principal,
        principal
      ) < rateModule.maxDTI(), "Should be under DTI"
    );
    assertTrue(
      rateModule.computeDTE(principal, agentValue) > rateModule.maxDTE(), "Should be over DTE"
    );
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
    pool.harvestFees(feesCollected);
    assertEq(asset.balanceOf(treasury), feesCollected);
  }
}

contract PoolAPRTests is PoolTestState {

  using FixedPointMathLib for uint256;

  // we know that a GCRED score of 80 should come out to be 22% APR rougly
  uint256 KNOWN_RATE = 22e16;

  function testGetRateAppliedAnnually() public {
    uint256 testRate = _getAdjustedRate(GCRED);

    uint256 chargedRatePerEpoch = pool.getRate(
      issueGenericBorrowCred(agentID, WAD).vc
    );

    assertEq(testRate, chargedRatePerEpoch, "Test rates should match");
    // annualRateMultiplier becomes WAD based after the divWadDown
    uint256 annualRateMultiplier = KNOWN_RATE.divWadDown(DEFAULT_BASE_RATE);
    // the perEpochMultiplier then gets another WAD added to it to make it more precise - (e18 * WAD / epochs (non WAD))
    // it's important to keep the perEpochMultiplier with an extra WAD to remain price at the epoch level
    uint256 perEpochMultiplier = annualRateMultiplier.divWadDown(EPOCHS_IN_YEAR);
    // computes what the per epoch rate should be, muls out the extra WAD in `perEpochMultiplier`
    uint256 expectedRate = DEFAULT_BASE_RATE.mulWadUp(perEpochMultiplier);
    // mulWadUp on EPOCHS (non WAD) then cancels out the final WAD present in `expectedRate`
    assertEq(expectedRate.mulWadUp(EPOCHS_IN_YEAR), KNOWN_RATE, "APR should be known APR value");
    assertEq(chargedRatePerEpoch.mulWadUp(EPOCHS_IN_YEAR), KNOWN_RATE, "APR should be known APR value");

    assertEq(
      chargedRatePerEpoch,
      expectedRate,
      "Charged rate should be known rate"
    );
    // NOTE: imprecision between different calculations of the per epoch rate, bth result in the same desired APR
    assertApproxEqAbs(
      chargedRatePerEpoch,
      KNOWN_RATE.divWadDown(EPOCHS_IN_YEAR),
      1e11,
      "Charged rate should be known rate"
    );
  }

  function testGetRateAppliedTenYears() public {
    uint256 KNOWN_RATE_10Y = KNOWN_RATE * 10;

    uint256 testRate = _getAdjustedRate(GCRED);

    uint256 chargedRatePerEpoch = pool.getRate(
      issueGenericBorrowCred(agentID, WAD).vc
    );

    assertEq(testRate, chargedRatePerEpoch, "Test rates should match");

    // adds 1 an extra wad (e16 * wad / e16)
    uint256 annualRateMultiplier = KNOWN_RATE.divWadDown(DEFAULT_BASE_RATE);
    // maintains 1 extra wad (e18 * wad / epochs * wad)
    uint256 perEpochMultiplier = annualRateMultiplier.divWadDown(EPOCHS_IN_YEAR);
    // computes what the per epoch rate should be, muls out the last extra WAD
    uint256 expectedRate = DEFAULT_BASE_RATE.mulWadUp(perEpochMultiplier);

    assertEq(expectedRate.mulWadUp(EPOCHS_IN_YEAR * 10), KNOWN_RATE_10Y, "APR should be known APR value");
    assertEq(chargedRatePerEpoch.mulWadUp(EPOCHS_IN_YEAR * 10), KNOWN_RATE_10Y, "APR should be known APR value");

    // NOTE: imprecision between different calculations of the per epoch rate, bth result in the same desired APR
    // I believe this is due to the fact that the KNOWN_RATE only specifies 4 digits of precision
    assertEq(
      chargedRatePerEpoch,
      expectedRate,
      "Charged rate should be known rate"
    );
    assertApproxEqAbs(
      chargedRatePerEpoch,
      KNOWN_RATE.divWadDown(EPOCHS_IN_YEAR),
      1e11,
      "Charged rate should be known rate"
    );
  }

  function testAPRKnownCREDSinglePayment(uint256 principal, uint256 collateralValue) public {
    principal = bound(principal, WAD, MAX_FIL / 2);
    collateralValue = bound(collateralValue, principal * 2, MAX_FIL);

    uint256 interestOwed = startSimulation(principal);

    Account memory accountBefore = AccountHelpers.getAccount(router, agentID, poolID);

    uint256 prePaymentPoolBal = wFIL.balanceOf(address(pool));
    uint256 payment = interestOwed;
    SignedCredential memory payCred = issuePayCred(
      agentID,
      principal,
      collateralValue,
      payment
    );
    // pay back the amount
    agentPay(agent, pool, payCred);

    Account memory accountAfter = AccountHelpers.getAccount(router, agentID, poolID);

    assertEq(accountAfter.principal, accountBefore.principal, "Principal should not change");
    assertEq(accountAfter.epochsPaid, block.number - 1, "Epochs paid should be up to date");

    assertPoolFundsSuccess(principal, interestOwed, prePaymentPoolBal);
  }

  function testAPRKnownGCRED(
    uint256 principal,
    uint256 collateralValue,
    uint256 numPayments
  ) public {
    principal = bound(principal, WAD, MAX_FIL / 2);
    collateralValue = bound(collateralValue, principal * 2, MAX_FIL);
    // test APR when making payments twice a week to once every two weeks
    numPayments = bound(numPayments, 26, 104);

    // borrow an amount
    uint256 interestOwed = startSimulation(principal);

    uint256 payment = interestOwed / numPayments;

    Account memory account = AccountHelpers.getAccount(router, agentID, poolID);
    uint256 prePaymentPoolBal = wFIL.balanceOf(address(pool));
    // since each payment is for the same amount, we memoize the first payment amount and assert the others against it
    uint256 epochsCreditForPayment;
    Account memory prevAccount = AccountHelpers.getAccount(router, agentID, poolID);
    for (uint256 i = 0; i < numPayments; i++) {
      SignedCredential memory payCred = issuePayCred(
        agentID,
        principal,
        collateralValue,
        payment
      );
      // pay back the amount
      agentPay(agent, pool, payCred);

      Account memory updatedAccount = AccountHelpers.getAccount(router, agentID, poolID);

      assertEq(updatedAccount.principal, prevAccount.principal, "Account principal not should have changed");
      assertGt(updatedAccount.epochsPaid, prevAccount.epochsPaid, "Account epochs paid should have increased");

      uint256 _epochsCreditForPayment = updatedAccount.epochsPaid - prevAccount.epochsPaid;
      if (i == 0) {
        epochsCreditForPayment = _epochsCreditForPayment;
      }

      if (_epochsCreditForPayment == 0) {
        // break the test early if it fails
        break;
      }
      assertGt(epochsCreditForPayment, 0, "Payment should have been made");
      assertEq(epochsCreditForPayment, _epochsCreditForPayment, "Payment should have been made for the same number of epochs");
      if (epochsCreditForPayment != _epochsCreditForPayment) {
        break;
      }

      prevAccount = updatedAccount;
    }

    Account memory newAccount = AccountHelpers.getAccount(router, agentID, poolID);

    assertEq(
      newAccount.principal,
      account.principal,
      "Principal should not change"
    );

    assertApproxEqAbs(
      newAccount.epochsPaid,
      // each payment shifts block.number forward by 1 by issuing a new cred, so we subtract that here for the assertion
      block.number - numPayments,
      // here our acceptance criteria is the number of payments because each payment moves the block.number forward (and some rounding)
      100,
      "Epochs paid should be up to date"
    );

    assertPoolFundsSuccess(principal, interestOwed, prePaymentPoolBal);
  }

  function assertPoolFundsSuccess(
    uint256 principal,
    uint256 interestOwed,
    uint256 prePaymentPoolBal
  ) internal {
    // 10,000,000 represents a factor of 10 larger than the years worth of epochs
    // so we lose 1 digit of precision for 10 years of epochs (since 1 year of epochs is roughly 1 million epochs, the next significant digit is at 10 million epochs)
    uint256 MAX_PRECISION_DELTA = 1e8;

    uint256 poolEarnings = wFIL.balanceOf(address(pool)) - prePaymentPoolBal;
    // ensures the pool got the interest
    assertApproxEqAbs(
      poolEarnings,
      interestOwed,
      DUST,
      "Pool should have received the owed interest"
    );

    // ensures the interest the pool got is what we'd expect
    assertApproxEqAbs(
      poolEarnings,
      KNOWN_RATE.mulWadUp(principal),
      MAX_PRECISION_DELTA,
      "Pool should have received the expected known amount"
    );

    uint256 treasuryFeeRate = GetRoute.poolRegistry(router).treasuryFeeRate();
    // ensures the pool got the right amount of fees
    assertApproxEqAbs(
      pool.feesCollected(),
      // fees collected should be treasury fee % of the interest earned
      poolEarnings.mulWadUp(treasuryFeeRate),
      DUST,
      "Treasury should have received the right amount of fees"
    );

    uint256 knownTreasuryFeeAmount = KNOWN_RATE.mulWadUp(principal).mulWadUp(treasuryFeeRate);

    // ensures the pool got the right amount of fees
    assertApproxEqAbs(
      pool.feesCollected(),
      // fees collected should be treasury fee % of the interest earned
      knownTreasuryFeeAmount,
      MAX_PRECISION_DELTA,
      "Treasury should have received the known amount of fees portion of principal delta precision"
    );
  }

  function startSimulation(uint256 principal) internal returns (uint256 interestOwed) {
    depositFundsIntoPool(pool, principal + WAD, makeAddr("Investor1"));
    SignedCredential memory borrowCred = issueGenericBorrowCred(agentID, principal);
    uint256 epochStart = block.number;
    agentBorrow(agent, poolID, borrowCred);

    // move forward a year
    vm.roll(block.number + EPOCHS_IN_YEAR);

    // compute how much we should owe in interest
    uint256 adjustedRate = _getAdjustedRate(GCRED);
    Account memory account = AccountHelpers.getAccount(router, agentID, poolID);

    assertEq(account.startEpoch, epochStart, "Account should have correct start epoch");
    assertEq(account.principal, principal, "Account should have correct principal");

    uint256 epochsToPay = block.number - account.epochsPaid;
    interestOwed = account.principal.mulWadUp(adjustedRate).mulWadUp(epochsToPay);
    assertGt(principal, interestOwed, "principal should be greater than interest owed for a GCRED of 80");
  }

  function issuePayCred(
    uint256 agentID,
    uint256 principal,
    uint256 collateralValue,
    uint256 paymentAmount
  ) internal returns (SignedCredential memory) {
    // here we temporarily roll forward so we don't get an identical credential that's already been used
    // then we roll it back to where it was so that we don't creep over a year's worth of epochs
    vm.roll(block.number + 1);

    uint256 adjustedRate = _getAdjustedRate(GCRED);

    AgentData memory agentData = createAgentData(
      collateralValue,
      // good gcred score
      GCRED,
      // good EDR
      adjustedRate.mulWadUp(principal).mulWadUp(EPOCHS_IN_DAY) * 5,
      principal
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agentID,
      block.number,
      block.number + 100,
      paymentAmount,
      Agent.pay.selector,
      // minerID irrelevant for pay action
      0,
      abi.encode(agentData)
    );

    // roll back in time to not mess with the "annual" part of the APR
    // vm.roll(block.number - index);

    return signCred(vc);
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
    (bool success, ) = address(pool).call{value: amount}("");
    assertTrue(success, "Address: unable to send value, recipient may have reverted");
    uint256 balanceAfter = asset.balanceOf(address(pool));
    assertEq(balanceAfter - balanceBefore, amount);
  }

  function testPoolFallbackFil() public {
    uint256 amount = WAD;
    vm.deal(investor1, amount);
    uint256 balanceBefore = asset.balanceOf(address(pool));
    vm.prank(investor1);
    (bool success, ) = address(pool).call{value: amount}(abi.encodeWithSignature("fakeFunction(uint256, uint256)", 1, 2));
    assertTrue(success, "Address: unable to send value, recipient may have reverted");
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
    vm.prank(address(poolRegistry));
    pool.jumpStartTotalBorrowed(amount);
    assertEq(pool.totalBorrowed(), amount);
  }

  function testJumpStartAccount(uint256 jumpStartAmount) public {
    jumpStartAmount = bound(jumpStartAmount, WAD, MAX_FIL);
    address receiver = makeAddr("receiver");
    (Agent newAgent,) = configureAgent(receiver);
    uint256 agentID = newAgent.id();
    vm.startPrank(IAuth(address(pool)).owner());
    pool.jumpStartAccount(receiver, agentID, jumpStartAmount);
    vm.stopPrank();

    uint256 balanceOfReceiver = pool.liquidStakingToken().balanceOf(receiver);

    Account memory account = AccountHelpers.getAccount(router, agentID, poolID);

    assertEq(account.principal, jumpStartAmount, "Account principal should be updated");
    assertEq(balanceOfReceiver, jumpStartAmount, "Should have minted liquid staking tokens");
    assertEq(account.startEpoch, block.number, "Account start epoch should be updated");
    assertEq(account.epochsPaid, block.number, "Account epochsPaid should be updated");

    // test making a payment
    uint256 payment = jumpStartAmount / 2;
    agentPay(IAgent(address(newAgent)), pool, issueGenericPayCred(agentID, payment));
  }

  function testJumpStartTotalBorrowedBadState() public {
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, WAD));
    vm.prank(address(poolRegistry));
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

  function testshutDownPool() public {
    assertEq(stakeAmount, asset.balanceOf(address(pool)));
    vm.prank(address(systemAdmin));
    pool.shutDown();
    assertTrue(pool.isShuttingDown(), "Pool should be shut down");
    vm.prank(address(poolRegistry));
  }

  function testUpgradePool(uint256 paymentAmt, uint256 initialBorrow) public {

    initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
    paymentAmt = bound(paymentAmt, WAD - DUST, initialBorrow - DUST);

    // Generate some fees to harvest
    _generateFees(paymentAmt, initialBorrow);
    uint256 fees = pool.feesCollected();
    uint256 treasuryBalance = asset.balanceOf(address(treasury));


    IPool newPool = IPool(new InfinityPool(
      systemAdmin,
      router,
      address(asset),
      address(pool.rateModule()),
      // no min liquidity for test pool
      address(liquidStakingToken),
      address(new PreStake(systemAdmin, IWFIL(address(wFIL)), IPoolToken(address(liquidStakingToken)))),
      0,
      poolID
    ));
    vm.prank(systemAdmin);
    liquidStakingToken.setMinter(address(newPool));

    // get stats before upgrade
    uint256 lstBalance = liquidStakingToken.balanceOf(investor1);
    uint256 totalBorrowed = pool.totalBorrowed();
    uint256 agentBorrowed = pool.getAgentBorrowed(agentID);
    uint256 assetBalance = asset.balanceOf(address(pool));

    // first shut down the pool
    vm.startPrank(systemAdmin);
    pool.shutDown();
    // then upgrade it
    poolRegistry.upgradePool(newPool);
    vm.stopPrank();

    // get stats after upgrade
    uint256 lstBalanceNew = newPool.liquidStakingToken().balanceOf(investor1);
    uint256 totalBorrowedNew = newPool.totalBorrowed();
    uint256 agentBorrowedNew = newPool.getAgentBorrowed(agentID);
    uint256 agentBalanceNew = wFIL.balanceOf(address(agent));
    uint256 assetBalanceNew = newPool.asset().balanceOf(address(newPool));

    // Test balances updated correctly through upgrade
    assertEq(lstBalanceNew, lstBalance, "LST balance should be the same");
    assertEq(totalBorrowedNew, totalBorrowed, "Total borrowed should be the same");
    assertEq(agentBorrowedNew, agentBorrowed, "Agent borrowed should be the same");
    assertEq(assetBalanceNew, assetBalance - fees, "Asset balance should be the same");
    assertEq(asset.balanceOf(treasury), treasuryBalance + fees, "Treasury should have received fees");

    assertNewPoolWorks(newPool, assetBalanceNew, agentBalanceNew);
  }

  function assertNewPoolWorks(IPool newPool, uint256 assetBalanceNew, uint256 agentWFILBal) internal {
    // deposit into the pool again
    address newInvestor = makeAddr("NEW_INVESTOR");
    uint256 newStakeAmount = borrowAmount;
    uint256 newLSTBal = newPool.previewDeposit(newStakeAmount);

    depositFundsIntoPool(newPool, WAD, newInvestor);

    assertEq(
      newPool.liquidStakingToken().balanceOf(newInvestor), newLSTBal,
      "Investor should have received new liquid staking tokens"
    );
    assertEq(
      wFIL.balanceOf(address(newPool)),
      assetBalanceNew + newStakeAmount,
      "Pool should have received new stake amount"
    );

    // Temporarily bump the epochsPaidBorrowBuffer so we can borrow
    _bumpMaxEpochsOwedTolerance(EPOCHS_IN_DAY*25, address(newPool));

    uint256 newBorrowAmount = newPool.totalBorrowableAssets();
    // Test that the new pool can be used to borrow
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, newPool.totalBorrowableAssets()));

    assertEq(wFIL.balanceOf(address(agent)), newBorrowAmount + agentWFILBal, "Agent should have received new borrow amount");
  }

  function testHarvestFeesTreasury(uint256 paymentAmt, uint256 initialBorrow, uint256 harvestAmount) public {
    initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
    paymentAmt = bound(paymentAmt, WAD - DUST, initialBorrow - DUST);
    // Generate some fees to harvest
    _generateFees(paymentAmt, initialBorrow);

    uint256 fees = pool.feesCollected();
    assertGt(fees, 0, "Fees should be greater than 0");
    uint256 treasuryBalance = asset.balanceOf(address(treasury));
    harvestAmount = bound(harvestAmount, 0, fees);

    vm.prank(systemAdmin);
    pool.harvestFees(harvestAmount);

    assertEq(pool.feesCollected(), fees - harvestAmount, "Fees should be reduced by harvest amount");
    assertEq(asset.balanceOf(address(treasury)), treasuryBalance + harvestAmount, "Treasury should have received harvest amount");
  }
}

contract PoolErrorBranches is PoolTestState {

  using FixedPointMathLib for uint256;

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

  function testPayUpBeforeBorrow(uint256 borrowAmount, uint256 rollFwdAmount) public {
    uint256 secondBorrowAmount = WAD;
    borrowAmount = bound(borrowAmount, WAD, stakeAmount - secondBorrowAmount - DUST);
    rollFwdAmount = bound(rollFwdAmount, 1, 42*EPOCHS_IN_DAY);
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, borrowAmount));
    vm.roll(block.number + rollFwdAmount);

    uint256 buffer = IInfinityPool(address(pool)).maxEpochsOwedTolerance();

    if (rollFwdAmount < buffer) {
      agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, secondBorrowAmount));
    } else {
      vm.startPrank(_agentOperator(agent));
      try agent.borrow(poolID, issueGenericBorrowCred(agentID, WAD)) {
        fail("Should not be able to borrow without paying up");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), InfinityPool.PayUp.selector);
      }
      vm.stopPrank();
    }
  }

  function testLiquidAssetsLessThanFees(
    uint256 initialBorrow,
    uint256 paymentAmt
  ) public {
    initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
    // ensure we have enough money to pay some interest
    uint256 minPayment = _getAdjustedRate(GCRED).mulWadUp(initialBorrow) / WAD;
    paymentAmt = bound(paymentAmt, minPayment + DUST, initialBorrow - DUST);
    assertGt(pool.getLiquidAssets(), 0, "Liquid assets should be greater than zero before pool is shut down");
    // Our first borrow is based on the payment amount to generate fees
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, initialBorrow));
    // Roll foward enough that at least _some_ payment is interest
    vm.roll(block.number + GetRoute.agentPolice(router).defaultWindow() - 1);
    agentPay(agent, pool, issueGenericPayCred(agentID, paymentAmt));

    // if we dont have enough to borrow, deposit enough to borrow the rest
    if (pool.totalBorrowableAssets() < WAD) {
      vm.startPrank(address(pool));
      vm.deal(address(pool), WAD);
      wFIL.deposit{value: WAD}();
      vm.stopPrank();
    }
    // temporarily bump the epochsPaidBorrowBuffer so we can borrow again
    _bumpMaxEpochsOwedTolerance(EPOCHS_IN_DAY*25, address(pool));
    // borrow the rest of the assets
    agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, pool.totalBorrowableAssets()));
    assertEq(pool.getLiquidAssets(), 0, "Liquid assets should be zero when pool is shutting down");
  }

  function testMintZeroShares() public {
    vm.prank(address(investor1));
    vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
    pool.mint(0, investor1);
  }
}

contract PoolPreStakeIntegrationTest is BaseTest {
  address preStake = makeAddr("PRE_STAKE");

  IInfinityPool pool;

  function setUp() public {
    pool = IInfinityPool(address(createPool()));
  }

  function testTransferFromPreStake(uint256 preStakeBal, uint256 transferFromAmt) public {
    vm.assume(transferFromAmt < preStakeBal);
    vm.deal(address(preStake), preStakeBal);

    vm.startPrank(address(preStake));
    wFIL.deposit{value: preStakeBal}();
    wFIL.approve(address(pool), preStakeBal);
    vm.stopPrank();

    uint256 wFILPoolBal = wFIL.balanceOf(address(pool));
    uint256 poolSharesIssued = pool.liquidStakingToken().totalSupply();

    vm.startPrank(IAuth(address(pool)).owner());
    pool.transferFromPreStake(preStake, transferFromAmt);

    assertEq(wFIL.balanceOf(address(pool)), wFILPoolBal + transferFromAmt);
    assertEq(pool.liquidStakingToken().totalSupply(), poolSharesIssued);
  }
}

contract PoolUpgradeCredentialTest is PoolTestState {
    using NewCredentials for VerifiableCredential;
    function testUpdateCredParser() public {
      _updateCredParser();
    }

    function testParsesOldCredential(uint256 principal) public {
      principal = bound(principal, WAD, stakeAmount);
      _updateCredParser();
      SignedCredential memory borrowCred = issueGenericBorrowCred(agentID, principal);
      agentBorrow(agent, poolID, borrowCred);
    }

    function testHasNewParameter(uint256 principal) public {
      principal = bound(principal, WAD, stakeAmount);
      _updateCredParser();
      uint256 collateralValue = principal * 2;
      // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
      uint256 lockedFunds = collateralValue * 167 / 100;
      // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
      uint256 agentValue = lockedFunds * 120 / 100;
      // NOTE: since we don't pull this off the pool it could be out of sync - careful
      uint256 adjustedRate = _getAdjustedRate(gCredBasic);

      NewAgentData memory agentData = NewAgentData(
        agentValue,
        collateralValue,
        // expectedDailyFaultPenalties
        0,
        (adjustedRate * EPOCHS_IN_DAY * principal * 5) / WAD,
        gCredBasic,
        lockedFunds,
        // qaPower hardcoded
        10e18,
        principal,
        block.number,
        12345 
      );

      

      VerifiableCredential memory vc = VerifiableCredential(
        vcIssuer,
        agentID,
        block.number,
        block.number + 100,
        principal,
        Agent.borrow.selector,
        // minerID irrelevant for borrow action
        0,
        abi.encode(agentData)
      );

      SignedCredential memory newCredential  =  signCred(vc);
      uint256 newParameter = NewCredentials.getNewVariable(newCredential.vc, newCredParser);
      assertEq(newParameter, 12345);
    }
}

contract PoolAccountingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;

    IAgent agent;
    uint64 miner;
    IPool pool;
    IPoolToken iFIL;

    address investor = makeAddr("INVESTOR");
    address minerOwner = makeAddr("MINER_OWNER");

    function setUp() public {
      pool = createPool();
      iFIL = pool.liquidStakingToken();
      (agent, miner) = configureAgent(minerOwner);
    }

    function testOverPayUnderTotalBorrowed() public {
      vm.startPrank(systemAdmin);
      GetRoute.poolRegistry(router).setTreasuryFeeRate(0);
      vm.stopPrank();

      (IAgent agent2,) = configureAgent(minerOwner);
      uint256 borrowAmountAgent1 = 10e18;
      uint256 payAmount = 20e18;
      uint256 borrowAmountAgent2 = 100e18;

      depositFundsIntoPool(pool, MAX_FIL, investor);

      // totalBorrowed should be a large number for this assertion
      agentBorrow(agent2, pool.id(), issueGenericBorrowCred(agent2.id(), borrowAmountAgent2));

      Account memory account2 = AccountHelpers.getAccount(router, agent2.id(), pool.id());
      assertEq(account2.principal, borrowAmountAgent2, "Account should have borrowed amount");
      _invPrincipalEqualsTotalBorrowed(pool, "test over pay under total borrowed 1");

      assertPegInTact(pool);

      agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), borrowAmountAgent1));

      _invPrincipalEqualsTotalBorrowed(pool, "test over pay under total borrowed 1.5");

      agentPay(agent, pool, issueGenericPayCred(agent.id(), payAmount));

      Account memory postPayAccount1 = AccountHelpers.getAccount(router, agent.id(), pool.id());
      Account memory postPayAccount2 = AccountHelpers.getAccount(router, agent2.id(), pool.id());
      assertEq(postPayAccount1.principal, 0, "Account should have been paid off");
      assertEq(postPayAccount2.principal, pool.totalBorrowed(), "Agent2 principal should equal pool's total borrowed");
      _invPrincipalEqualsTotalBorrowed(pool, "test over pay under total borrowed 2");
    }
}

contract PoolStakingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;

    IAgent agent;
    uint64 miner;
    IPool pool;
    IPoolToken iFIL;

    address investor = makeAddr("INVESTOR");
    address minerOwner = makeAddr("MINER_OWNER");

    function setUp() public {
      pool = createPool();
      iFIL = pool.liquidStakingToken();
      (agent, miner) = configureAgent(minerOwner);
    }

    function testDepositTwice(uint256 stakeAmount) public {
      stakeAmount = bound(stakeAmount, WAD, MAX_FIL);

      vm.deal(investor, MAX_FIL);
      vm.startPrank(investor);

      // first we put WAD worth of FIL in the pool to block inflation attacks
      uint256 sharesFromInitialDeposit = pool.deposit{value: WAD}(investor);
      assertEq(sharesFromInitialDeposit, WAD, "Shares should be equal to WAD");

      uint256 sharesFromSecondDeposit = pool.deposit{value: stakeAmount}(investor);
      assertEq(sharesFromSecondDeposit, stakeAmount, "Shares should be equal to stakeAmount");
      vm.stopPrank();
    }
}

// // a value we use to test approximation of the cursor according to a window start/close
// // TODO: investigate how to get this to 0 or 1
// uint256 constant EPOCH_CURSOR_ACCEPTANCE_DELTA = 1;

// contract PoolStakingTest is BaseTest {
//   using Credentials for VerifiableCredential;
//   IAgent agent;

//   IPoolRegistry poolRegistry;
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
//     poolRegistry = IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
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

//   IPoolRegistry poolRegistry;
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
//     poolRegistry = IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
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

//   IPoolRegistry poolRegistry;
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
//     poolRegistry = IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
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


//   IPoolRegistry poolRegistry;
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
//     poolRegistry = IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
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


//   IPoolRegistry poolRegistry;
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
//     poolRegistry = IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
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


//   IPoolRegistry poolRegistry;
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
//     poolRegistry = GetRoute.poolRegistry(router);
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

//   IPoolRegistry poolRegistry;
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
//     poolRegistry = GetRoute.poolRegistry(router);
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

//   function testSetImplementation() public {
//     address newImplementation = makeAddr("NEW_IMPLEMENTATION");
//     // expect this call to revert because the implementation is not approved
//     vm.expectRevert("Pool: Invalid implementation");
//     vm.prank(poolOperator);
//     pool.setImplementation(IPoolImplementation(newImplementation));

//     // approve the Implementation
//     vm.prank(IAuth(address(poolRegistry)).owner());
//     poolRegistry.approveImplementation(newImplementation);

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
