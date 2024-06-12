// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase
pragma solidity ^0.8.17;

import "./BaseTest.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";

import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {NewCredParser} from "test/helpers/NewCredParser.sol";
import {NewCredentials, NewAgentData} from "test/helpers/NewCredentials.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";

contract PoolTestState is BaseTest {
    error InvalidState();

    using Credentials for VerifiableCredential;

    IPool pool;
    IPoolRegistry poolRegistry;
    uint256 borrowAmount = WAD;
    uint256 stakeAmount = 1000e18;
    uint256 expectedRateBasic = 15e16;
    uint256 goodEDR = 0.01e18;
    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    SignedCredential borrowCredBasic;
    VerifiableCredential vcBasic;
    IAgent agent;
    uint64 miner;
    IPoolToken public liquidStakingToken;
    IERC20 public asset;
    uint256 agentID;
    uint256 poolID;
    address newCredParser;

    function setUp() public virtual {
        (pool, agent, miner, borrowCredBasic, vcBasic) =
            poolBasicSetup(stakeAmount, borrowAmount, investor1, minerOwner);
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

    function _updateCredParser() internal {
        newCredParser = address(new NewCredParser());
        vm.startPrank(systemAdmin);
        Router(router).pushRoute(ROUTE_CRED_PARSER, newCredParser);
        pool.refreshRoutes();
        assertEq(pool.credParser(), newCredParser);
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
        vm.roll(block.number + (EPOCHS_IN_WEEK * 3));
        agentPay(agent, pool, issueGenericPayCred(agentID, paymentAmt));
    }
}

contract PoolBasicSetupTest is BaseTest {
    using Credentials for VerifiableCredential;

    IPool pool;
    uint256 borrowAmount = WAD;
    uint256 stakeAmount = 1000e18;
    uint256 expectedRateBasic = 15e18;
    uint256 goodEDR = 0.01e18;
    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    SignedCredential borrowCredBasic;
    VerifiableCredential vcBasic;
    IAgent agent;
    uint64 miner;

    function testCreatePool() public {
        IPoolRegistry poolRegistry = GetRoute.poolRegistry(router);
        PoolToken liquidStakingToken = new PoolToken(systemAdmin);
        uint256 id = poolRegistry.allPoolsLength();
        pool = IPool(
            new InfinityPool(
                systemAdmin,
                router,
                // no min liquidity for test pool
                address(liquidStakingToken),
                ILiquidityMineSP(address(0)),
                0,
                id
            )
        );
        assertEq(pool.id(), id, "pool id not set");
        assertEq(address(pool.asset()), address(wFIL), "pool asset not set");
        assertEq(IAuth(address(pool)).owner(), systemAdmin, "pool owner not set");
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
        uint256 treasuryFeesOwed = pool.treasuryFeesReserved();
        pool.harvestFees(treasuryFeesOwed);
        assertEq(asset.balanceOf(treasury), treasuryFeesOwed);
    }
}

contract PoolAPRTests is PoolTestState {
    using FixedPointMathLib for uint256;

    // we know that the rate is 15%
    uint256 KNOWN_RATE = 15e16;

    function testGetRateAppliedAnnually() public {
        // we borrow the full assets of the pool so we can apply the interest on the pool's total assets (no utilization rate decrease in rates)
        uint256 totalAssets = pool.totalAssets();
        // deposit 1 FIL in the test
        uint256 borrowAmt = totalAssets;
        uint256 testRate = _getAdjustedRate();

        uint256 chargedRatePerEpoch = pool.getRate();

        assertEq(chargedRatePerEpoch.mulWadUp(EPOCHS_IN_YEAR), KNOWN_RATE, "APR should be known APR value");
        assertEq(testRate, chargedRatePerEpoch, "Test rates should match");

        // here we can fake borrow 1 FIL from the pool, fast forward a year, and measure the returns of the pool
        agentBorrow(agent, poolID, _issueGenericBorrowCred(agent.id(), borrowAmt));

        // fast forward a year
        vm.roll(block.number + EPOCHS_IN_YEAR);
        _invIFILWorthAssetsOfPool(pool, "testGetRateAppliedAnnually");

        // compute the interest owed
        assertEq(
            pool.totalAssets(),
            totalAssets + totalAssets.mulWadDown(KNOWN_RATE).mulWadUp(1e18 - pool.treasuryFeeRate()),
            "Pool should have KNOWN RATE increase worth of asset"
        );
    }

    function testGetRateAppliedTenYears() public {
        // we borrow the full assets of the pool so we can apply the interest on the pool's total assets (no utilization rate decrease in rates)
        uint256 totalAssets = pool.totalAssets();
        // deposit 1 FIL in the test
        uint256 borrowAmt = totalAssets;
        uint256 chargedRatePerEpoch = pool.getRate();

        assertEq(chargedRatePerEpoch.mulWadUp(EPOCHS_IN_YEAR * 10), KNOWN_RATE * 10, "APR should be known APR value");

        // here we can fake borrow 1 FIL from the pool, fast forward a year, and measure the returns of the pool
        agentBorrow(agent, poolID, _issueGenericBorrowCred(agent.id(), borrowAmt));

        // fast forward a year
        vm.roll(block.number + EPOCHS_IN_YEAR * 10);

        _invIFILWorthAssetsOfPool(pool, "testGetRateAppliedAnnually");

        // compute the interest owed
        assertEq(
            pool.totalAssets(),
            totalAssets + totalAssets.mulWadDown(KNOWN_RATE * 10).mulWadUp(1e18 - pool.treasuryFeeRate()),
            "Pool should have KNOWN RATE increase worth of asset"
        );
    }

    function testCashBasisAPYSinglePayment(uint256 principal, uint256 collateralValue) public {
        principal = bound(principal, WAD, MAX_FIL / 2);
        collateralValue = bound(collateralValue, principal * 2, MAX_FIL);

        uint256 interestOwed = startSimulation(principal);
        // move forward a year
        vm.roll(block.number + EPOCHS_IN_YEAR);

        Account memory accountBefore = AccountHelpers.getAccount(router, agentID, poolID);

        uint256 prePaymentPoolBal = wFIL.balanceOf(address(pool));
        uint256 payment = interestOwed;
        SignedCredential memory payCred = issuePayCred(agentID, principal, collateralValue, payment);
        // pay back the amount
        agentPay(agent, pool, payCred);

        Account memory accountAfter = AccountHelpers.getAccount(router, agentID, poolID);

        assertEq(accountAfter.principal, accountBefore.principal, "Principal should not change");
        assertEq(accountAfter.epochsPaid, block.number, "Epochs paid should be up to date");

        assertPoolFundsSuccess(principal, interestOwed, prePaymentPoolBal);
    }

    function testCashBasisAPYManyPayments(uint256 principal, uint256 collateralValue, uint256 numPayments) public {
        principal = bound(principal, WAD, MAX_FIL / 2);
        collateralValue = bound(collateralValue, principal * 2, MAX_FIL);
        // test APR when making payments twice a week to once every two weeks
        numPayments = bound(numPayments, 26, 104);

        // borrow an amount
        uint256 interestOwed = startSimulation(principal);

        Account memory account = AccountHelpers.getAccount(router, agentID, poolID);
        uint256 prePaymentPoolBal = wFIL.balanceOf(address(pool));

        // since each payment is for the same amount, we memoize the first payment amount and assert the others against it
        Account memory prevAccount = AccountHelpers.getAccount(router, agentID, poolID);
        uint256 startBlock = block.number;
        uint256 endBlock = startBlock + EPOCHS_IN_YEAR;
        uint256 epochsCreditForPayment;
        for (uint256 i = 0; i <= numPayments; i++) {
            // if we're already at the end of the year, we can't make any more payments
            if (block.number >= endBlock) break;
            uint256 rollTo = block.number + (EPOCHS_IN_YEAR / numPayments);
            // reset the rollto block to be at the exact year end epoch for test assertion precision
            if (rollTo > endBlock) rollTo = endBlock;
            vm.roll(rollTo);
            SignedCredential memory payCred =
                issuePayCred(agentID, principal, collateralValue, pool.getAgentInterestOwed(agentID));

            // pay back the amount
            agentPay(agent, pool, payCred);

            Account memory updatedAccount = AccountHelpers.getAccount(router, agentID, poolID);

            assertEq(updatedAccount.principal, prevAccount.principal, "Account principal not should have changed");
            assertGt(updatedAccount.epochsPaid, prevAccount.epochsPaid, "Account epochs paid should have increased");

            epochsCreditForPayment = updatedAccount.epochsPaid - prevAccount.epochsPaid;
            assertGt(epochsCreditForPayment, 0, "Payment should have been made");

            prevAccount = updatedAccount;
        }

        Account memory newAccount = AccountHelpers.getAccount(router, agentID, poolID);

        assertEq(endBlock, block.number, "Should have rolled to the end of the year");
        assertEq(newAccount.principal, account.principal, "Principal should not change");
        assertEq(pool.getAgentInterestOwed(agentID), 0, "Interest owed should be 0");
        assertEq(newAccount.epochsPaid, block.number, "Epochs paid should be up to date");

        assertPoolFundsSuccess(principal, interestOwed, prePaymentPoolBal);
    }

    function assertPoolFundsSuccess(uint256 principal, uint256 interestOwed, uint256 prePaymentPoolBal) internal {
        uint256 poolEarnings = wFIL.balanceOf(address(pool)) - prePaymentPoolBal;
        // ensures the pool got the interest
        assertApproxEqAbs(poolEarnings, interestOwed, DUST, "Pool should have received the owed interest");

        // ensures the interest the pool got is what we'd expect
        assertApproxEqAbs(
            poolEarnings, KNOWN_RATE.mulWadUp(principal), DUST, "Pool should have received the expected known amount"
        );

        uint256 treasuryFeeRate = GetRoute.poolRegistry(router).treasuryFeeRate();
        // ensures the pool got the right amount of fees
        assertApproxEqAbs(
            pool.treasuryFeesReserved(),
            // fees collected should be treasury fee % of the interest earned
            poolEarnings.mulWadUp(treasuryFeeRate),
            DUST,
            "Treasury should have received the right amount of fees"
        );

        uint256 knownTreasuryFeeAmount = KNOWN_RATE.mulWadUp(principal).mulWadUp(treasuryFeeRate);

        // ensures the pool got the right amount of fees
        assertApproxEqAbs(
            pool.treasuryFeesReserved(),
            // fees collected should be treasury fee % of the interest earned
            knownTreasuryFeeAmount,
            DUST,
            "Treasury should have received the known amount of fees portion of principal delta precision"
        );
    }

    function startSimulation(uint256 principal) internal returns (uint256 interestOwed) {
        depositFundsIntoPool(pool, principal + WAD, makeAddr("Investor1"));
        SignedCredential memory borrowCred = _issueGenericBorrowCred(agentID, principal);
        uint256 epochStart = block.number;
        agentBorrow(agent, poolID, borrowCred);

        // compute how much we should owe in interest
        uint256 adjustedRate = _getAdjustedRate();
        Account memory account = AccountHelpers.getAccount(router, agentID, poolID);

        assertEq(account.startEpoch, epochStart, "Account should have correct start epoch");
        assertEq(account.principal, principal, "Account should have correct principal");

        interestOwed = account.principal.mulWadUp(adjustedRate).mulWadUp(EPOCHS_IN_YEAR);
        assertGt(principal, interestOwed, "principal should be greater than interest owed");
    }

    function issuePayCred(uint256 agentID, uint256 principal, uint256 collateralValue, uint256 paymentAmount)
        internal
        returns (SignedCredential memory)
    {
        uint256 adjustedRate = _getAdjustedRate();

        AgentData memory agentData = createAgentData(
            collateralValue,
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

        return signCred(vc);
    }
}

contract Pool4626Tests is PoolTestState {
    function setUp() public override {
        super.setUp();
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
        (bool success,) = address(pool).call{value: amount}("");
        assertTrue(success, "Address: unable to send value, recipient may have reverted");
        uint256 balanceAfter = asset.balanceOf(address(pool));
        assertEq(balanceAfter - balanceBefore, amount);
    }

    function testPoolFallbackFil() public {
        uint256 amount = WAD;
        vm.deal(investor1, amount);
        uint256 balanceBefore = asset.balanceOf(address(pool));
        vm.prank(investor1);
        (bool success,) =
            address(pool).call{value: amount}(abi.encodeWithSignature("fakeFunction(uint256, uint256)", 1, 2));
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

    function testshutDownPool() public {
        assertEq(stakeAmount, asset.balanceOf(address(pool)));
        vm.prank(address(systemAdmin));
        pool.shutDown();
        assertTrue(pool.isShuttingDown(), "Pool should be shut down");
        vm.prank(address(poolRegistry));
    }

    function testPayAfterShutDown() public {
        uint256 stakeAmount = 100e18;
        uint256 initialPoolAssets = pool.totalAssets();
        uint256 initialPoolTotalBorrowableAssets = pool.totalBorrowableAssets();

        vm.deal(investor1, stakeAmount);
        vm.prank(investor1);
        pool.deposit{value: stakeAmount}(investor1);

        uint256 totalBorrowable = pool.totalBorrowableAssets();

        assertEq(pool.totalAssets(), stakeAmount + initialPoolAssets, "pool should have assets");
        assertEq(initialPoolTotalBorrowableAssets + stakeAmount, totalBorrowable, "pool should have borrowable assets");

        agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, totalBorrowable));
        assertEq(agent.liquidAssets(), totalBorrowable, "Agent should have stakeAmount assets after borrowing");
        assertEq(pool.totalAssets(), stakeAmount + initialPoolAssets, "pool should have assets");
        assertEq(pool.totalBorrowableAssets(), 0, "pool should have no borrowable assets");

        vm.prank(systemAdmin);
        pool.shutDown();

        assertEq(agent.liquidAssets(), totalBorrowable, "Agent should have stakeAmount assets after borrowing");

        uint256 prePayBal = wFIL.balanceOf(address(pool));
        agentPay(agent, pool, issueGenericPayCred(agentID, stakeAmount));
        assertApproxEqAbs(pool.totalAssets(), initialPoolAssets + stakeAmount, 1e18, "pool should have assets");
        assertEq(pool.totalBorrowableAssets(), 0, "pool should have no borrowable assets after shutdown payment");
        assertEq(wFIL.balanceOf(address(pool)), prePayBal + stakeAmount, "pool should have received payment");
    }

    function testFallbackAfterShutDown() public {
        vm.prank(address(systemAdmin));
        pool.shutDown();
        assertTrue(pool.isShuttingDown(), "Pool should be shut down");

        address depositor = makeAddr("depositor");
        vm.deal(depositor, WAD);
        uint256 beforeBal = depositor.balance;
        vm.startPrank(depositor);
        vm.expectRevert(abi.encodeWithSelector(InvalidState.selector));
        // ignore return value of low-level calls not used compiler warning
        (bool success,) = address(pool).call{value: WAD}("");
        // not sure why this returns true
        assertTrue(success, "Not sure?");
        assertEq(beforeBal, WAD, "Depositor should still have its funds");
        vm.stopPrank();
    }

    function testUpgradePool(uint256 paymentAmt, uint256 initialBorrow) public {
        initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
        paymentAmt = bound(paymentAmt, WAD - DUST, initialBorrow - DUST);

        // Generate some fees to harvest
        _generateFees(paymentAmt, initialBorrow);
        uint256 fees = pool.treasuryFeesReserved();
        uint256 treasuryBalance = asset.balanceOf(address(treasury));

        IPool newPool = IPool(
            new InfinityPool(
                systemAdmin,
                router,
                // no min liquidity for test pool
                address(liquidStakingToken),
                ILiquidityMineSP(address(0)),
                0,
                poolID
            )
        );
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
            newPool.liquidStakingToken().balanceOf(newInvestor),
            newLSTBal,
            "Investor should have received new liquid staking tokens"
        );
        assertEq(
            wFIL.balanceOf(address(newPool)),
            assetBalanceNew + newStakeAmount,
            "Pool should have received new stake amount"
        );

        // Make a payment to get the account's epochsPaid current
        Account memory account = AccountHelpers.getAccount(router, agent.id(), newPool.id());
        vm.deal(address(agent), account.principal);

        agentPay(agent, newPool, issueGenericPayCred(agentID, account.principal));

        uint256 newBorrowAmount = newPool.totalBorrowableAssets();
        // Test that the new pool can be used to borrow
        agentBorrow(agent, newPool.id(), issueGenericBorrowCred(agentID, newPool.totalBorrowableAssets()));

        assertEq(
            wFIL.balanceOf(address(agent)),
            newBorrowAmount + agentWFILBal,
            "Agent should have received new borrow amount"
        );
    }

    function testHarvestFeesTreasury(uint256 paymentAmt, uint256 initialBorrow, uint256 harvestAmount) public {
        initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
        paymentAmt = bound(paymentAmt, WAD - DUST, initialBorrow - DUST);
        // Generate some fees to harvest
        _generateFees(paymentAmt, initialBorrow);

        uint256 fees = pool.treasuryFeesReserved();
        assertGt(fees, 0, "Fees should be greater than 0");
        uint256 treasuryBalance = asset.balanceOf(address(treasury));
        harvestAmount = bound(harvestAmount, 0, fees);

        vm.prank(systemAdmin);
        pool.harvestFees(harvestAmount);

        assertEq(pool.treasuryFeesReserved(), fees - harvestAmount, "Fees should be reduced by harvest amount");
        assertEq(
            asset.balanceOf(address(treasury)),
            treasuryBalance + harvestAmount,
            "Treasury should have received harvest amount"
        );
    }
}

contract PoolErrorBranches is PoolTestState {
    using FixedPointMathLib for uint256;

    function testTotalBorrowableZero(uint256 borrowAmount) public {
        uint256 balance = asset.balanceOf(address(pool));
        uint256 minLiquidity = pool.getAbsMinLiquidity();
        borrowAmount = bound(borrowAmount, balance - minLiquidity, balance);
        agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, borrowAmount));
        assertEq(pool.totalBorrowableAssets(), 0, "Total borrowable should be zero");
    }

    function testLiquidAssetsOnShutdown() public {
        uint256 liquidAssets = pool.getLiquidAssets();
        assertGt(liquidAssets, 0, "Liquid assets should be greater than zero before pool is shut down");
        vm.prank(address(systemAdmin));
        pool.shutDown();
        assertTrue(pool.isShuttingDown(), "Pool should be shut down");
        assertEq(pool.getLiquidAssets(), liquidAssets, "Liquid assets should be the same when pool is shutting down");
    }

    function testLiquidAssetsLessThanFees(uint256 initialBorrow, uint256 paymentAmt) public {
        initialBorrow = bound(initialBorrow, WAD, pool.totalBorrowableAssets());
        // ensure we have enough money to pay some interest
        uint256 minPayment = _getAdjustedRate().mulWadUp(initialBorrow) / WAD;
        paymentAmt = bound(paymentAmt, minPayment + DUST, initialBorrow - DUST);
        assertGt(pool.getLiquidAssets(), 0, "Liquid assets should be greater than zero before pool is shut down");
        // Our first borrow is based on the payment amount to generate fees
        agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, initialBorrow));
        // Roll foward enough that at least _some_ payment is interest
        vm.roll(block.number + EPOCHS_IN_WEEK * 3);
        agentPay(agent, pool, issueGenericPayCred(agentID, paymentAmt));

        // if we dont have enough to borrow, deposit enough to borrow the rest
        if (pool.totalBorrowableAssets() < WAD) {
            address investor = makeAddr("investor1");
            vm.deal(investor, WAD);
            vm.prank(investor);
            pool.deposit{value: WAD}(investor);
        }
        // pay back principal so we can borrow again
        Account memory account = AccountHelpers.getAccount(router, agentID, poolID);
        agentPay(agent, pool, issueGenericPayCred(agentID, account.principal));
        // borrow the rest of the assets
        agentBorrow(agent, poolID, issueGenericBorrowCred(agentID, pool.totalBorrowableAssets()));
        assertEq(pool.getLiquidAssets(), 0, "Liquid assets should be zero when liquid assets less than fees");
        assertGt(pool.treasuryFeesReserved(), 0, "Pool should have generated fees");
    }

    function testMintZeroShares() public {
        vm.prank(address(investor1));
        vm.expectRevert(abi.encodeWithSelector(InvalidParams.selector));
        pool.mint(0, investor1);
    }
}

// TODO: REIMPLEMENT CRED changing tests
// contract PoolUpgradeCredentialTest is PoolTestState {
//     using NewCredentials for VerifiableCredential;
//     function testUpdateCredParser() public {
//       _updateCredParser();
//     }

//     function testHasNewParameter(uint256 principal) public {
//       principal = bound(principal, WAD, stakeAmount);
//       _updateCredParser();
//       uint256 collateralValue = principal * 2;
//       // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
//       uint256 lockedFunds = collateralValue * 167 / 100;
//       // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
//       uint256 agentValue = lockedFunds * 120 / 100;
//       // NOTE: since we don't pull this off the pool it could be out of sync - careful
//       uint256 adjustedRate = _getAdjustedRate();

//       NewAgentData memory agentData = NewAgentData(
//         agentValue,
//         collateralValue,
//         // expectedDailyFaultPenalties
//         0,
//         (adjustedRate * EPOCHS_IN_DAY * principal * 5) / WAD,
//         gCredBasic,
//         lockedFunds,
//         // qaPower hardcoded
//         10e18,
//         principal,
//         block.number,
//         0,
//         1e18,
//         12345
//       );

//       VerifiableCredential memory vc = VerifiableCredential(
//         vcIssuer,
//         agentID,
//         block.number,
//         block.number + 100,
//         principal,
//         Agent.borrow.selector,
//         // minerID irrelevant for borrow action
//         0,
//         abi.encode(agentData)
//       );

//       SignedCredential memory newCredential  =  signCred(vc);
//       uint256 newParameter = NewCredentials.getNewVariable(newCredential.vc, newCredParser);
//       assertEq(newParameter, 12345);
//     }
// }

contract PoolAccountingTest is BaseTest {
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

    function testPayAfterLiquidation(uint256 payAmount) public {
        payAmount = bound(payAmount, 1, MAX_FIL);
        uint256 stakeAmount = 100e18;
        uint64 liquidatorID = 1;
        depositFundsIntoPool(pool, stakeAmount, investor);

        // borrow half the pool's assets, default, then pay everything back to the pool (as interest)
        agentBorrow(agent, pool.id(), issueGenericBorrowCred(agent.id(), stakeAmount / 2));

        vm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 toAssets = pool.convertToAssets(WAD);
        uint256 toShares = pool.convertToShares(WAD);

        IAgentPolice police = GetRoute.agentPolice(router);
        vm.startPrank(systemAdmin);
        // TODO: fix this
        // police.setAgentDefaulted(address(agent));
        police.prepareMinerForLiquidation(address(agent), miner, liquidatorID);
        police.distributeLiquidatedFunds(address(agent), 0);
        vm.stopPrank();

        uint256 toAssetsAfterLiquidating = pool.convertToAssets(WAD);
        uint256 toSharesAfterLiquidating = pool.convertToShares(WAD);

        assertEq(agent.defaulted(), true, "Agent should be defaulted");
        Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
        assertEq(account.defaulted, true, "Account should be defaulted");

        assertEq(pool.totalBorrowed(), 0, "Pool should have no total borrowed");
        assertEq(
            pool.getLiquidAssets(),
            stakeAmount / 2,
            "Pool should have half its liquid assets after losing everything else"
        );
        assertEq(toAssetsAfterLiquidating, toAssets / 2, "iFIL should be worth half");
        assertEq(toSharesAfterLiquidating, toShares * 2, "iFIL should be worth half");
        assertEq(pool.totalBorrowableAssets(), stakeAmount / 2, "Pool should have half as many total borrowable assets");

        vm.deal(address(agent), payAmount);
        vm.startPrank(_agentOperator(agent));
        agent.pay(pool.id(), issueGenericPayCred(agent.id(), payAmount));
        vm.stopPrank();

        assertEq(pool.totalBorrowed(), 0, "Pool should still have no total borrowed");

        uint256 fee = GetRoute.poolRegistry(router).treasuryFeeRate().mulWadUp(payAmount);
        uint256 payAmountLessFee = payAmount - fee;

        assertApproxEqAbs(
            pool.getLiquidAssets(),
            (stakeAmount / 2) + payAmountLessFee,
            1e16,
            "Pool should have payAmount added to its liquid assets"
        );
        assertApproxEqAbs(
            pool.totalBorrowableAssets(),
            (stakeAmount / 2) + payAmountLessFee,
            1e16,
            "Pool should have payAmount added to total borrowable assets"
        );
        // if pay amount is greater than 1e16, then the iFIL should be worth more (bc of treasury fees)
        if (payAmount > 1e16) {
            assertGt(pool.convertToAssets(WAD), toAssetsAfterLiquidating, "iFIL should be worth more");
            assertGt(toSharesAfterLiquidating, pool.convertToShares(WAD), "iFIL should be worth more");
        }
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
        assertEq(
            pool.convertToAssets(shares),
            rewardAmount + stakeAmount,
            "Preview redeem should equal stake amount + reward amount"
        );

        // mint wad shares, expect to get back
        uint256 mintDepositAmount = WAD;
        // assets here should be more than the mintDepositAmount by the price of iFIL denominated in FIL
        uint256 assets = pool.mint(mintDepositAmount, investor);
        // since we 50% appreciated on pool assets, it should br 1.5x the assets required to mint the mintDepositAmount
        assertEq(assets, mintDepositAmount * 3 / 2, "Assets should be 1.5x the mint amount");

        shares = pool.deposit(mintDepositAmount, investor);
        assertEq(
            shares,
            mintDepositAmount * 2 / 3,
            "Shares received should be 50% less than mintDepositAmount after appreciation"
        );
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
        assertEq(
            pool.convertToAssets(shares),
            rewardAmount + stakeAmount,
            "Preview redeem should equal stake amount + reward amount"
        );

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

// these tests mock out all other contracts so we can isolate the infinity pool code for testing
contract PoolIsolationTests is BaseTest {
    using FixedPointMathLib for uint256;

    uint256 public constant _DUST = 1e3;

    IPool public pool;
    address public investor = makeAddr("INVESTOR");

    address[] public agents = [makeAddr("AGENT1")];

    // charge 1% of borrow amount per epoch in these tests to simply math assertions
    uint256 public rentalFeesPerEpoch;

    function setUp() public {
        pool = createPool();
        rentalFeesPerEpoch = pool.getRate();
    }

    // this test goes through various states of the pool with a single depositor and borrower to make assertions about totalAssets
    function testFuzzTotalAssets(uint256 depositAmount, uint256 rollFwd) public {
        _mockAgentFactoryAgentsCalls();
        uint64 agentID = 1;
        address agent = agents[agentID - 1];
        depositAmount = bound(depositAmount, 1e18, MAX_FIL);
        rollFwd = bound(rollFwd, 1, EPOCHS_IN_YEAR);
        uint256 borrowAmount = depositAmount;
        uint256 startBlock = block.number;

        // at the start, total assets should be 0
        assertEq(pool.totalAssets(), 0, "Total assets should be 0 before any assets are added");

        // after a deposit, total assets should equal the deposit amount
        vm.deal(investor, depositAmount);
        pool.deposit{value: depositAmount}(investor);

        assertEq(
            pool.totalAssets(), depositAmount, "Total assets should equal the deposit amount after initial deposit"
        );

        // after a borrow, total assets should not change
        VerifiableCredential memory vc = _issueGenericBorrowCred(agentID, borrowAmount).vc;
        vm.startPrank(agent);
        pool.borrow(vc);
        vm.stopPrank();

        assertEq(pool.totalAssets(), depositAmount, "Total assets should equal the deposit amount after initial borrow");

        // after a block goes by, interest should accrue, increasing total assets
        vm.roll(block.number + 1);

        // the expected accrued interest should be 1% of the borrow amount, minus treasury fee
        uint256 expectedTotalInterest = borrowAmount.mulWadUp(rentalFeesPerEpoch).mulWadUp(1);
        uint256 expectedAccruedRentalFees = expectedTotalInterest.mulWadUp(1e18 - pool.treasuryFeeRate());
        uint256 accountInterestOwed = pool.getAgentInterestOwed(agentID);

        assertApproxEqAbs(
            accountInterestOwed,
            expectedTotalInterest,
            _DUST,
            "Account interest owed should equal the expected interest"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest"
        );

        // after a payment is made, total assets should stay the same
        uint256 paymentAmount = accountInterestOwed;

        vc = _issueGenericPayCred(agentID, paymentAmount).vc;

        // give the agent the payment amount of fil
        vm.deal(agent, paymentAmount);
        vm.startPrank(agent);
        wFIL.approve(address(pool), paymentAmount);
        pool.pay(vc);
        vm.stopPrank();

        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest after a payment"
        );

        // after harvesting treasury fees, total assets should stay the same
        vm.prank(systemAdmin);
        pool.harvestFees(pool.treasuryFeesReserved());

        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest after a harvest"
        );

        // roll forward to accrue more interest
        vm.roll(block.number + rollFwd);

        expectedTotalInterest = borrowAmount.mulWadUp(rentalFeesPerEpoch).mulWadUp(block.number - startBlock);
        expectedAccruedRentalFees = expectedTotalInterest.mulWadUp(1e18 - pool.treasuryFeeRate());

        assertEq(pool.totalBorrowed(), borrowAmount, "Total borrowed should equal the borrow amount");
        assertApproxEqAbs(
            pool.getAgentInterestOwed(agentID) + paymentAmount,
            expectedTotalInterest,
            _DUST,
            "Account interest owed + paid should equal the expected interest - 2"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest - 2"
        );
    }

    function _testTotalAssetsAfterLiquidationPartialRecovery() public {}

    function _testTotalAssetsAfterLiquidationFullRecovery() public {}

    function testFuzzAccruedRentalFeesEqualTotalDebtAccruedOnAccounts(
        uint256 agentCount,
        uint256 depositAmt,
        uint256 rollFwd
    ) public {
        uint256 startBlock = block.number;
        // first lets load in a number of agents to the agent factory
        agentCount = bound(agentCount, 1, 20);
        depositAmt = bound(depositAmt, 1e18, MAX_FIL / agentCount);
        rollFwd = bound(rollFwd, 1, EPOCHS_IN_YEAR);
        agents = new address[](agentCount);
        for (uint256 i = 0; i < agentCount; i++) {
            agents[i] = makeAddr(string(abi.encodePacked("AGENT", vm.toString(i))));
        }
        _mockAgentFactoryAgentsCalls();
        // in this test we make multiple accounts, roll forward, and test that the accrued debt on each account matches the total accrued debt for the pool
        uint256 depositAmount = depositAmt * agents.length;
        // borrow the full amount in the pool
        uint256 borrowAmount = depositAmt;

        // after a deposit, total assets should equal the deposit amount
        vm.deal(investor, depositAmount);
        pool.deposit{value: depositAmount}(investor);

        // borrow FIL from all the agents
        for (uint256 i = 0; i < agents.length; i++) {
            uint256 agentID = i + 1;
            address agent = agents[i];
            VerifiableCredential memory vc = _issueGenericBorrowCred(agentID, borrowAmount).vc;
            vm.prank(agent);
            pool.borrow(vc);
        }

        assertEq(
            pool.totalAssets(), depositAmount, "Total assets should equal the deposit amount when nothing is borrowed"
        );

        // roll forward to accrue interest
        vm.roll(block.number + 1);

        // the expected accrued interest should be 1% of the borrow amount, minus treasury fee
        uint256 expectedTotalInterest = (borrowAmount * agents.length).mulWadUp(rentalFeesPerEpoch).mulWadUp(1);
        uint256 expectedAccruedRentalFees = expectedTotalInterest.mulWadUp(1e18 - pool.treasuryFeeRate());
        uint256 expectedTotalInterestFromAccounts;
        for (uint256 i = 0; i < agents.length; i++) {
            uint256 agentID = i + 1;
            expectedTotalInterestFromAccounts += pool.getAgentInterestOwed(agentID);
        }

        // check that the total accrued rental fees match the expected interest
        assertEq(
            pool.accruedRentalFees(),
            expectedTotalInterest,
            "Total accrued rental fees should equal the expected interest"
        );
        assertApproxEqAbs(
            pool.accruedRentalFees(),
            expectedTotalInterestFromAccounts,
            _DUST,
            "Total accrued rental fees should equal the expected interest from accounts"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest"
        );

        uint256 totalPayments;

        // make payments and make the same assertions
        for (uint256 i = 0; i < agents.length; i++) {
            uint256 agentID = i + 1;
            address agent = agents[i];
            uint256 paymentAmount = pool.getAgentInterestOwed(agentID);
            totalPayments += paymentAmount;

            VerifiableCredential memory vc = _issueGenericPayCred(agentID, paymentAmount).vc;
            // give the agent the payment amount of fil
            vm.deal(agent, paymentAmount);
            vm.startPrank(agent);
            wFIL.approve(address(pool), paymentAmount);
            pool.pay(vc);
            vm.stopPrank();
        }

        // check that the total accrued rental fees match the expected interest
        assertEq(
            pool.accruedRentalFees(),
            expectedTotalInterest,
            "Total accrued rental fees should equal the expected interest"
        );
        assertApproxEqAbs(
            pool.accruedRentalFees(),
            expectedTotalInterestFromAccounts,
            _DUST,
            "Total accrued rental fees should equal the expected interest from accounts"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest"
        );
        assertApproxEqAbs(
            pool.paidRentalFees(), expectedTotalInterest, _DUST, "Paid rental fees should equal the expected interest"
        );

        // roll forward to accrue more interest
        vm.roll(block.number + rollFwd);

        // the expected accrued interest should be 1% of the borrow amount, minus treasury fee
        expectedTotalInterest =
            (borrowAmount * agents.length).mulWadUp(rentalFeesPerEpoch).mulWadUp(block.number - startBlock);
        expectedAccruedRentalFees = expectedTotalInterest.mulWadUp(1e18 - pool.treasuryFeeRate());
        expectedTotalInterestFromAccounts = 0;
        for (uint256 i = 0; i < agents.length; i++) {
            uint256 agentID = i + 1;
            expectedTotalInterestFromAccounts += pool.getAgentInterestOwed(agentID);
        }

        // check that the total accrued rental fees match the expected interest
        assertApproxEqAbs(
            pool.accruedRentalFees(),
            expectedTotalInterest,
            _DUST,
            "Total accrued rental fees should equal the expected interest"
        );
        assertApproxEqAbs(
            pool.accruedRentalFees(),
            expectedTotalInterestFromAccounts + totalPayments,
            _DUST,
            "Total accrued rental fees should equal the expected interest from accounts + total payments"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            // here we use expectedAccruedRentalFees because it accounts for treasury fees
            depositAmount + (expectedTotalInterestFromAccounts + totalPayments).mulWadUp(1e18 - pool.treasuryFeeRate()),
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest plus the total payments derived from accounts"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest"
        );
    }

    // test ensures that even if we make a lot of payments, the pool accounting holds up
    function testFuzzManyPaymentsTotalAssets(uint256 numPayments, uint256 rollFwd, uint256 depositAmount) public {
        numPayments = bound(numPayments, 3, 100);
        rollFwd = bound(rollFwd, numPayments, EPOCHS_IN_YEAR);
        depositAmount = bound(depositAmount, 1e18, MAX_FIL);
        _mockAgentFactoryAgentsCalls();
        uint256 agentID = 1;
        address agent = agents[agentID - 1];
        uint256 startBlock = block.number;

        uint256 borrowAmount = depositAmount;

        // after a deposit, total assets should equal the deposit amount
        vm.deal(investor, depositAmount);
        pool.deposit{value: depositAmount}(investor);

        // after a borrow, total assets should not change
        VerifiableCredential memory vc = _issueGenericBorrowCred(agentID, borrowAmount).vc;
        vm.startPrank(agent);
        pool.borrow(vc);
        vm.stopPrank();

        // make interest payments over numpayments
        uint256 expectedTotalInterest = borrowAmount.mulWadUp(rentalFeesPerEpoch).mulWadUp(rollFwd);
        vm.deal(agent, expectedTotalInterest);
        vm.startPrank(agent);
        // make sure we have enough WFIL to pay the interest
        wFIL.deposit{value: expectedTotalInterest}();
        wFIL.approve(address(pool), expectedTotalInterest + borrowAmount);

        uint256 totalPayments;
        for (uint256 i = 0; i < numPayments; i++) {
            // if this is the last payment, roll forward to the end of the period to get to the end of the rollfwd period
            if (i == numPayments - 1) {
                vm.roll(rollFwd + startBlock);
            } else {
                vm.roll(block.number + (rollFwd / numPayments));
            }
            uint256 paymentAmt = pool.getAgentInterestOwed(agentID);
            totalPayments += paymentAmt;
            vc = _issueGenericPayCred(agentID, paymentAmt).vc;
            pool.pay(vc);
        }

        vm.stopPrank();
        uint256 expectedAccruedRentalFees = expectedTotalInterest.mulWadUp(1e18 - pool.treasuryFeeRate());
        uint256 totalFeesPaid = pool.paidRentalFees();
        assertApproxEqAbs(
            totalFeesPaid, expectedTotalInterest, _DUST, "Total fees paid should equal the expected interest"
        );
        assertApproxEqAbs(
            pool.totalAssets(),
            depositAmount + expectedAccruedRentalFees,
            _DUST,
            "Total assets should equal the deposit amount plus the expected interest"
        );
        assertEq(pool.getAgentInterestOwed(agentID), 0, "Agent interest owed should be 0 after all payments");
        assertEq(
            AccountHelpers.getAccount(router, agentID, 0).epochsPaid,
            block.number,
            "Agent should have paid for all epochs"
        );
    }

    function _mockAgentFactoryAgentsCalls() internal {
        for (uint256 i = 0; i < agents.length; i++) {
            address agent = agents[i];
            // mock a call to the agent factory about the agent to give it an ID
            vm.mockCall(
                address(GetRoute.agentFactory(router)),
                abi.encodeWithSelector(bytes4(keccak256("agents(address)")), agent),
                abi.encode(i + 1)
            );
        }
    }
}
