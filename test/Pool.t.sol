// SPDX-License-Identifier: BUSL-1.1
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
  }

  function _updateCredParser() internal {
    newCredParser = address(new NewCredParser());
    vm.startPrank(systemAdmin);
    Router(router).pushRoute(ROUTE_CRED_PARSER, newCredParser);
    pool.rateModule().updateCredParser();
    assertEq(pool.rateModule().credParser(), newCredParser);
    vm.stopPrank();
  }

  function _mintApproveLST(uint256 amount, address target, address spender) internal {
    vm.prank(address(pool));
    liquidStakingToken.mint(target, amount);
    vm.prank(target);
    liquidStakingToken.approve(address(spender), amount);
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
      address investor = makeAddr("investor1");
      vm.deal(investor, WAD);
      vm.prank(investor);
      pool.deposit{value: WAD}(investor);
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
      testInvariants(pool, "test over pay under total borrowed 1");

      assertPegInTact(pool);

      agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), borrowAmountAgent1));

      testInvariants(pool, "test over pay under total borrowed 1.5");

      agentPay(agent, pool, issueGenericPayCred(agent.id(), payAmount));

      Account memory postPayAccount1 = AccountHelpers.getAccount(router, agent.id(), pool.id());
      Account memory postPayAccount2 = AccountHelpers.getAccount(router, agent2.id(), pool.id());
      assertEq(postPayAccount1.principal, 0, "Account should have been paid off");
      assertEq(postPayAccount2.principal, pool.totalBorrowed(), "Agent2 principal should equal pool's total borrowed");
      testInvariants(pool, "test over pay under total borrowed 2");
    }
}

contract PoolStakingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;

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

    function testDepositFILTwice(uint256 stakeAmount) public {
      stakeAmount = bound(stakeAmount, 1, MAX_FIL);

      vm.deal(investor, MAX_FIL);
      vm.startPrank(investor);

      // first we put WAD worth of FIL in the pool to block inflation attacks
      uint256 sharesFromInitialDeposit = pool.deposit{value: WAD}(investor);
      assertEq(sharesFromInitialDeposit, WAD, "Shares should be equal to WAD");

      uint256 sharesFromSecondDeposit = pool.deposit{value: stakeAmount}(investor);
      assertEq(sharesFromSecondDeposit, stakeAmount, "Shares should be equal to stakeAmount");
      vm.stopPrank();
      testInvariants(pool, "test deposit fil twice");
    }

    function testDepositTwice(uint256 stakeAmount) public {
      stakeAmount = bound(stakeAmount, 1, MAX_FIL);

      vm.deal(investor, MAX_FIL);
      vm.startPrank(investor);

      wFIL.deposit{value: stakeAmount + WAD}();
      wFIL.approve(address(pool), stakeAmount + WAD);

      // first we put WAD worth of FIL in the pool to block inflation attacks
      uint256 sharesFromInitialDeposit = pool.deposit(WAD, investor);
      assertEq(sharesFromInitialDeposit, WAD, "Shares should be equal to WAD");

      uint256 sharesFromSecondDeposit = pool.deposit(stakeAmount, investor);
      assertEq(sharesFromSecondDeposit, stakeAmount, "Shares should be equal to stakeAmount");
      vm.stopPrank();
      testInvariants(pool, "test deposit twice");
    }

    function testMintTwice(uint256 mintAmount) public {
      mintAmount = bound(mintAmount, 1, MAX_FIL);

      vm.deal(investor, MAX_FIL);
      vm.startPrank(investor);

      wFIL.deposit{value: mintAmount + WAD}();
      wFIL.approve(address(pool), mintAmount + WAD);

      // first we put WAD worth of FIL in the pool to block inflation attacks
      uint256 sharesFromInitialDeposit = pool.mint(WAD, investor);
      assertEq(sharesFromInitialDeposit, WAD, "Shares should be equal to WAD");

      uint256 sharesFromSecondDeposit = pool.mint(mintAmount, investor);
      assertEq(sharesFromSecondDeposit, mintAmount, "Shares should be equal to mintAmount");
      vm.stopPrank();
      testInvariants(pool, "test mint twice");
    }

    function testMintDepositZero() public {
      vm.startPrank(investor);
      vm.expectRevert(InvalidParams.selector);
      pool.mint(0, address(this));

      vm.expectRevert(InvalidParams.selector);
      pool.deposit(0, address(this));
      vm.stopPrank();
      testInvariants(pool, "test mint deposit zero");
    }

    function testMintDepositForReceiver(string memory seed, uint256 amount) public {
      amount = bound(amount, 1, MAX_FIL);

      address receiver = makeAddr(seed);

      vm.deal(investor, amount * 2 + WAD);
      vm.startPrank(investor);

      wFIL.deposit{value: amount * 2 + WAD}();
      wFIL.approve(address(pool), amount * 2 + WAD);

      uint256 preDepositIFILBal = iFIL.balanceOf(receiver);

      pool.deposit(amount, receiver);

      uint256 postDepositIFILBal = iFIL.balanceOf(receiver);

      assertEq(postDepositIFILBal - preDepositIFILBal, amount, "Receiver should have received minted iFIL");

      pool.mint(amount, receiver);

      uint256 postMintIFILBal = iFIL.balanceOf(receiver);

      assertEq(postMintIFILBal - postDepositIFILBal, amount, "Receiver should have received minted iFIL");

      vm.stopPrank();
      testInvariants(pool, "testMintDepositForReceiver");
    }

    function testMintAfterKnownPoolTokenAppreciation() public {
      uint256 stakeAmount = 100e18;
      uint256 rewardAmount = 50e18;

      vm.startPrank(investor);
      vm.deal(investor, MAX_FIL);
      wFIL.deposit{value: MAX_FIL}();
      wFIL.approve(address(pool), MAX_FIL);

      uint256 shares = pool.deposit(stakeAmount, investor);
      assertEq(pool.liquidStakingToken().totalSupply(), shares, "Total supply should equal shares");
      assertEq(pool.convertToAssets(shares), stakeAmount, "Preview redeem should equal stake amount");
      assertPegInTact(pool);
      // next we want to double the pool's asset
      // we do this by transferring the rewards amount directly into the pool
      wFIL.transfer(address(pool), rewardAmount);
      // expecting to convert to assets should cause rewardAmount % increase in price
      assertEq(pool.convertToAssets(shares), rewardAmount + stakeAmount, "Preview redeem should equal stake amount + reward amount");

      // mint wad shares, expect to get back 
      uint256 mintDepositAmount = WAD;
      // assets here should be more than the mintDepositAmount by the price of iFIL denominated in FIL
      uint256 assets = pool.mint(mintDepositAmount, investor);
      // since we 50% appreciated on pool assets, it should br 1.5x the assets required to mint the mintDepositAmount
      assertEq(assets, mintDepositAmount * 3 / 2, "Assets should be 1.5x the mint amount");

      shares = pool.deposit(mintDepositAmount, investor);
      assertEq(shares, mintDepositAmount * 2 / 3, "Shares received should be 50% less than mintDepositAmount after appreciation");
      testInvariants(pool, "testMintAfterKnownPoolTokenAppreciation");
    }

    function testMintDepositAfterPoolTokenAppreciation(uint256 stakeAmount, uint256 rewardAmount) public {
      stakeAmount = bound(stakeAmount, WAD, MAX_FIL / 2);
      rewardAmount = bound(rewardAmount, WAD, MAX_FIL / 2);

      vm.startPrank(investor);
      vm.deal(investor, MAX_FIL * 3);
      wFIL.deposit{value: MAX_FIL * 3}();
      wFIL.approve(address(pool), MAX_FIL * 3);

      uint256 shares = pool.deposit(stakeAmount, investor);
      assertEq(pool.liquidStakingToken().totalSupply(), shares, "Total supply should equal shares");
      assertEq(pool.convertToAssets(shares), stakeAmount, "Preview redeem should equal stake amount");
      assertPegInTact(pool);
      // next we want to appreciate the pool's asset
      // we do this by transferring the rewards amount directly into the pool
      wFIL.transfer(address(pool), rewardAmount);
      // expecting to convert to assets should cause rewardAmount % increase in price
      assertEq(pool.convertToAssets(shares), rewardAmount + stakeAmount, "Preview redeem should equal stake amount + reward amount");

      uint256 mintDepositAmount = WAD;
      // assets here should be more than the mintDepositAmount by the price of iFIL denominated in FIL
      uint256 assets = pool.mint(mintDepositAmount, investor);
      // appreciate by difference in assets
      uint256 appreciation = (rewardAmount + stakeAmount).divWadDown(stakeAmount);

      assertApproxEqAbs(assets, appreciation.mulWadDown(mintDepositAmount), 1, "Assets should include appreciation");
      assertGt(assets, mintDepositAmount, "Assets paid should be greater than mint amount");

      shares = pool.deposit(WAD, investor);

      assertApproxEqAbs(shares, mintDepositAmount.divWadDown(appreciation), 1, "Assets should include appreciation");
      assertLt(shares, mintDepositAmount, "Assets paid should be greater than mint amount");

      testInvariants(pool, "testMintDepositAfterPoolTokenAppreciation");
    }

    function testRecursiveDepositMintAfterDepeg(uint256 runs, uint256 depegAmt) public {
      runs = bound(runs, 1, 1000);
      depegAmt = bound(depegAmt, WAD, 1e27);

      // first depeg iFIL to make sure it holds after depegging
      vm.startPrank(investor);
      vm.deal(investor, MAX_FIL);
      wFIL.deposit{value: MAX_FIL}();
      wFIL.approve(address(pool), MAX_FIL);

      pool.deposit(WAD, investor);
      wFIL.transfer(address(pool), depegAmt);

      uint256 begConvertToShares = pool.convertToShares(WAD);
      uint256 begConvertToAssets = pool.convertToAssets(WAD);

      assertLt(begConvertToShares, WAD, "iFIL should have depegged");
      assertGt(begConvertToAssets, WAD, "iFIL should have depgged");

      for (uint256 i = 0; i < runs; i++) {
        uint256 convertToShares = pool.convertToShares(WAD);
        uint256 convertToAssets = pool.convertToAssets(WAD);
        pool.deposit(WAD, investor);
        assertApproxEqRel(pool.convertToAssets(WAD), convertToAssets, 1e3, "iFIL should not have depegged again");
        assertApproxEqRel(pool.convertToShares(WAD), convertToShares, 1e3, "iFIL should not have depegged again");
      }

      assertApproxEqRel(pool.convertToAssets(WAD), begConvertToAssets, 1e3, "iFIL should not have depegged again");
      assertApproxEqRel(pool.convertToShares(WAD), begConvertToShares, 1e3, "iFIL should not have depegged again");

      testInvariants(pool, "testRecursiveDepositMintAfterDepeg");
    }
}
