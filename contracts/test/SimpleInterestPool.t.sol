// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Pool/SimpleInterestPool.sol";
import "src/WFIL.sol";
import "src/MockMiner.sol";
import "src/LoanAgent/ILoanAgent.sol";

import "./BaseTest.sol";

contract SimpleInterestPoolStakingTest is BaseTest {
  address investor1 = makeAddr("INVESTOR_1");
  address investor2 = makeAddr("INVESTOR_2");
  string poolName = "TEST 20% Simple Interest Pool";
  uint256 baseInterestRate = 20e18;

  IPool4626 simpleInterestPool;
  function setUp() public {
    simpleInterestPool = poolFactory.createSimpleInterestPool(poolName, baseInterestRate);

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 1e18}();
    require(wFIL.balanceOf(investor1) == 1e18);
  }

  function testAsset() public {
    ERC20 asset = simpleInterestPool.asset();
    assertEq(asset.name(), "Wrapped Filecoin");
    assertEq(asset.symbol(), "WFIL");
    assertEq(asset.decimals(), 18);
  }

  function testPoolToken() public {
    assertEq(simpleInterestPool.name(), poolName);
    // assertEq(simpleInterestPool.symbol(), poolSymbol);
    assertEq(simpleInterestPool.decimals(), 18);
  }

  function testSingleDepositWithdraw() public {
    uint256 investor1UnderlyingAmount = 1e18;

    vm.prank(investor1);
    wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
    assertEq(wFIL.allowance(investor1, address(simpleInterestPool)), investor1UnderlyingAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    vm.prank(investor1);
    uint256 investor1ShareAmount = simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);

    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount);
    assertEq(simpleInterestPool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(simpleInterestPool.totalSupply(), investor1ShareAmount);
    assertEq(simpleInterestPool.totalAssets(), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(investor1), investor1ShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    simpleInterestPool.withdraw(investor1UnderlyingAmount, investor1, investor1);

    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(investor1), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor1)), 0);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal);
  }

  function testSingleMintRedeem() public {
    uint256 investor1ShareAmount = 1e18;

    vm.prank(investor1);
    wFIL.approve(address(simpleInterestPool), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(simpleInterestPool)), investor1ShareAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    vm.prank(investor1);
    uint256 investor1UnderlyingAmount = simpleInterestPool.mint(investor1ShareAmount, investor1);

    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(investor1ShareAmount, investor1UnderlyingAmount);
    assertEq(simpleInterestPool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(simpleInterestPool.totalSupply(), investor1ShareAmount);
    assertEq(simpleInterestPool.totalAssets(), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(investor1), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    simpleInterestPool.redeem(investor1ShareAmount, investor1, investor1);

    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(investor1), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor1)), 0);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal);
  }

  function testMultipleMintDepositRedeemWithdraw() public {
    address rewardsActor = address(0xAAAA);
    vm.deal(rewardsActor, 10 ether);
    vm.prank(rewardsActor);
    wFIL.deposit{value: 10 ether}();

    // Scenario:
    // A = Arthur, B = investor2
    //  ________________________________________________________
    // | Pool shares | A share | A assets | B share | B assets |
    // |========================================================|
    // | 1. Arthur mints 2000 shares (costs 2000 tokens)         |
    // |--------------|---------|----------|---------|----------|
    // |         2000 |    2000 |     2000 |       0 |        0 |
    // |--------------|---------|----------|---------|----------|
    // | 2. investor2 deposits 4000 tokens (mints 4000 shares)        |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     2000 |    4000 |     4000 |
    // |--------------|---------|----------|---------|----------|
    // | 3. Pool mutates by +3000 tokens...                    |
    // |    (simulated yield returned from strategy)...         |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     3000 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 4. Arthur deposits 2000 tokens (mints 1333 shares)      |
    // |--------------|---------|----------|---------|----------|
    // |         7333 |    3333 |     4999 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 5. investor2 mints 2000 shares (costs 3001 assets)           |
    // |    NOTE: investor2's assets spent got rounded up             |
    // |    NOTE: Arthur's simpleInterestPool assets got rounded up           |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     5000 |    6000 |     9000 |
    // |--------------|---------|----------|---------|----------|
    // | 6. Vault mutates by +3000 tokens...                    |
    // |    (simulated yield returned from strategy)            |
    // |    NOTE: Vault holds 17001 tokens, but sum of          |
    // |          assetsOf() is 17000.                          |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     6071 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 7. Arthur redeem 1333 shares (2428 assets)              |
    // |--------------|---------|----------|---------|----------|
    // |         8000 |    2000 |     3643 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 8. investor2 withdraws 2928 assets (1608 shares)             |
    // |--------------|---------|----------|---------|----------|
    // |         6392 |    2000 |     3643 |    4392 |     8000 |
    // |--------------|---------|----------|---------|----------|
    // | 9. Arthur withdraws 3643 assets (2000 shares)           |
    // |    NOTE: investor2's assets have been rounded back up        |
    // |--------------|---------|----------|---------|----------|
    // |         4392 |       0 |        0 |    4392 |     8001 |
    // |--------------|---------|----------|---------|----------|
    // | 10. investor2 redeem 4392 shares (8001 tokens)               |
    // |--------------|---------|----------|---------|----------|
    // |            0 |       0 |        0 |       0 |        0 |
    // |______________|_________|__________|_________|__________|

    address arthur = address(0xBADC);
    vm.deal(arthur, 1e18);
    vm.deal(investor2, 1e18);

    uint256 mutationUnderlyingAmount = 3000;


    vm.startPrank(arthur);
    wFIL.deposit{value: 4000}();

    wFIL.approve(address(simpleInterestPool), 4000);
    vm.stopPrank();

    assertEq(wFIL.allowance(arthur, address(simpleInterestPool)), 4000);

    vm.startPrank(investor2);
    wFIL.deposit{value: 7001}();
    wFIL.approve(address(simpleInterestPool), 7001);
    vm.stopPrank();

    assertEq(wFIL.allowance(investor2, address(simpleInterestPool)), 7001);

    // 1. Arthur mints 2000 shares (costs 2000 tokens)
    vm.prank(arthur);
    uint256 investor1UnderlyingAmount = simpleInterestPool.mint(2000, arthur);

    uint256 investor1ShareAmount = simpleInterestPool.previewDeposit(investor1UnderlyingAmount);

    // Expect to have received the requested mint amount.
    assertEq(investor1ShareAmount, 2000);
    assertEq(simpleInterestPool.balanceOf(arthur), investor1ShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), investor1UnderlyingAmount);
    assertEq(simpleInterestPool.convertToShares(investor1UnderlyingAmount), simpleInterestPool.balanceOf(arthur));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor1UnderlyingAmount, 2000);

    // Sanity check.
    assertEq(simpleInterestPool.totalSupply(), investor1ShareAmount);
    assertEq(simpleInterestPool.totalAssets(), investor1UnderlyingAmount);

    // 2. investor2 deposits 4000 tokens (mints 4000 shares)
    vm.prank(investor2);
    uint256 investor2ShareAmount = simpleInterestPool.deposit(4000, investor2);
    uint256 investor2UnderlyingAmount = simpleInterestPool.previewWithdraw(investor2ShareAmount);

    // Expect to have received the requested wFIL amount.
    assertEq(investor2UnderlyingAmount, 4000);
    assertEq(simpleInterestPool.balanceOf(investor2), investor2ShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), investor2UnderlyingAmount);
    assertEq(simpleInterestPool.convertToShares(investor2UnderlyingAmount), simpleInterestPool.balanceOf(investor2));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor2ShareAmount, investor2UnderlyingAmount);

    // Sanity check.
    uint256 preMutationShareBal = investor1ShareAmount + investor2ShareAmount;
    uint256 preMutationBal = investor1UnderlyingAmount + investor2UnderlyingAmount;
    assertEq(simpleInterestPool.totalSupply(), preMutationShareBal);
    assertEq(simpleInterestPool.totalAssets(), preMutationBal);
    assertEq(simpleInterestPool.totalSupply(), 6000);
    assertEq(simpleInterestPool.totalAssets(), 6000);

    // 3. Pool mutates by +3000 tokens...                    |
    //    (simulated yield returned from strategy)...
    // The Pool now contains more tokens than deposited which causes the exchange rate to change.
    // Arthur share is 33.33% of the Pool, investor 2 66.66% of the Pool.
    // Arthur's share count stays the same but the wFIL amount changes from 2000 to 3000.
    // investor 2's share count stays the same but the wFIL amount changes from 4000 to 6000.
    vm.prank(rewardsActor);
    wFIL.transfer(address(simpleInterestPool), mutationUnderlyingAmount);

    assertEq(simpleInterestPool.totalSupply(), preMutationShareBal);
    assertEq(simpleInterestPool.totalAssets(), preMutationBal + mutationUnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(arthur), investor1ShareAmount);
    assertEq(
        simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)),
        investor1UnderlyingAmount + (mutationUnderlyingAmount / 3) * 1
    );
    assertEq(simpleInterestPool.balanceOf(investor2), investor2ShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), investor2UnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

    // 4. investor1 deposits 2000 tokens (mints 1333 shares)
    vm.prank(arthur);
    simpleInterestPool.deposit(2000, arthur);

    assertEq(simpleInterestPool.totalSupply(), 7333);
    assertEq(simpleInterestPool.balanceOf(arthur), 3333);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 4999);
    assertEq(simpleInterestPool.balanceOf(investor2), 4000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 6000);

    // 5. investor 2 mints 2000 shares (costs 3001 assets)
    // NOTE: investor 2's assets spent got rounded up
    // NOTE: investor1's simpleInterestPool assets got rounded up
    vm.prank(investor2);
    simpleInterestPool.mint(2000, investor2);

    assertEq(simpleInterestPool.totalSupply(), 9333);
    assertEq(simpleInterestPool.balanceOf(arthur), 3333);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 5000);
    assertEq(simpleInterestPool.balanceOf(investor2), 6000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 9000);

    // Sanity checks:
    // investor1 and investor2 should have spent all their tokens now
    assertEq(wFIL.balanceOf(arthur), 0);
    assertEq(wFIL.balanceOf(investor2), 0);
    // Assets in simpleInterestPool: 4k (arthur) + 7k (investor2) + 3k (yield) + 1 (round up)
    assertEq(simpleInterestPool.totalAssets(), 14001);

    // 6. Vault mutates by +3000 tokens
    // NOTE: Vault holds 17001 tokens, but sum of assetsOf() is 17000.
    vm.prank(rewardsActor);
    wFIL.transfer(address(simpleInterestPool), mutationUnderlyingAmount);
    assertEq(simpleInterestPool.totalAssets(), 17001);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 6071);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 10929);

    // 7. investor1 redeem 1333 shares (2428 assets)
    vm.prank(arthur);
    simpleInterestPool.redeem(1333, arthur, arthur);

    assertEq(wFIL.balanceOf(arthur), 2428);
    assertEq(simpleInterestPool.totalSupply(), 8000);
    assertEq(simpleInterestPool.totalAssets(), 14573);
    assertEq(simpleInterestPool.balanceOf(arthur), 2000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 3643);
    assertEq(simpleInterestPool.balanceOf(investor2), 6000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 10929);

    // 8. investor2 withdraws 2929 assets (1608 shares)
    vm.prank(investor2);
    simpleInterestPool.withdraw(2929, investor2, investor2);

    assertEq(wFIL.balanceOf(investor2), 2929);
    assertEq(simpleInterestPool.totalSupply(), 6392);
    assertEq(simpleInterestPool.totalAssets(), 11644);
    assertEq(simpleInterestPool.balanceOf(arthur), 2000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 3643);
    assertEq(simpleInterestPool.balanceOf(investor2), 4392);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 8000);

    // 9. investor1 withdraws 3643 assets (2000 shares)
    // NOTE: investor 2's assets have been rounded back up
    vm.prank(arthur);
    simpleInterestPool.withdraw(3643, arthur, arthur);

    assertEq(wFIL.balanceOf(arthur), 6071);
    assertEq(simpleInterestPool.totalSupply(), 4392);
    assertEq(simpleInterestPool.totalAssets(), 8001);
    assertEq(simpleInterestPool.balanceOf(arthur), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 0);
    assertEq(simpleInterestPool.balanceOf(investor2), 4392);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 8001);

    // 10. investor2 redeem 4392 shares (8001 tokens)
    vm.prank(investor2);
    simpleInterestPool.redeem(4392, investor2, investor2);
    assertEq(wFIL.balanceOf(investor2), 10930);
    assertEq(simpleInterestPool.totalSupply(), 0);
    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(arthur), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 0);
    assertEq(simpleInterestPool.balanceOf(investor2), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(investor2)), 0);

    // Sanity check
    assertEq(wFIL.balanceOf(address(simpleInterestPool)), 0);
  }

  // function testTotalAssets() public {
  //   assertTrue(true);
  // }
  // function testConvertToShares() public {
  //   assertTrue(true);
  // }
  // function testConvertToAssets() public {
  //   assertTrue(true);
  // }

  // function testDeposit() public {
  //   assertTrue(true);
  // }
  // function testMaxDeposit() public {
  //   assertTrue(true);
  // }
  // function testPreviewDeposit() public {
  //   assertTrue(true);
  // }

  // function testWithdraw() public {
  //   assertTrue(true);
  // }
  // function testPreviewWithdraw() public {
  //   assertTrue(true);
  // }
  // function testMaxWithdraw() public {
  //   assertTrue(true);
  // }

  // function testMint() public {
  //   assertTrue(true);
  // }
  // function testMaxMint() public {
  //   assertTrue(true);
  // }
  // function testPreviewMint() public {
  //   assertTrue(true);
  // }

  // function testRedeem() public {
  //   assertTrue(true);
  // }
  // function testMaxRedeem() public {
  //   assertTrue(true);
  // }
  // function testPreviewRedeem() public {
  //   assertTrue(true);
  // }

    function testFailDepositWithNotEnoughApproval() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(simpleInterestPool), 0.5e18);
        assertEq(wFIL.allowance(address(this), address(simpleInterestPool)), 0.5e18);

        simpleInterestPool.deposit(1e18, address(this));
    }

    function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(simpleInterestPool), 0.5e18);

        simpleInterestPool.deposit(0.5e18, address(this));

        simpleInterestPool.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughShareAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(simpleInterestPool), 0.5e18);

        simpleInterestPool.deposit(0.5e18, address(this));

        simpleInterestPool.redeem(1e18, address(this), address(this));
    }

    function testFailWithdrawWithNoUnderlyingAmount() public {
        simpleInterestPool.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNoShareAmount() public {
        simpleInterestPool.redeem(1e18, address(this), address(this));
    }

    function testFailDepositWithNoApproval() public {
        simpleInterestPool.deposit(1e18, address(this));
    }

    function testFailMintWithNoApproval() public {
        simpleInterestPool.mint(1e18, address(this));
    }

    function testFailDepositZero() public {
        simpleInterestPool.deposit(0, address(this));
    }

    function testMintZero() public {
        simpleInterestPool.mint(0, address(this));

        assertEq(simpleInterestPool.balanceOf(address(this)), 0);
        assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(address(this))), 0);
        assertEq(simpleInterestPool.totalSupply(), 0);
        assertEq(simpleInterestPool.totalAssets(), 0);
    }

    function testFailRedeemZero() public {
        simpleInterestPool.redeem(0, address(this), address(this));
    }

    function testWithdrawZero() public {
        simpleInterestPool.withdraw(0, address(this), address(this));

        assertEq(simpleInterestPool.balanceOf(address(this)), 0);
        assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(address(this))), 0);
        assertEq(simpleInterestPool.totalSupply(), 0);
        assertEq(simpleInterestPool.totalAssets(), 0);
    }
}

contract SimpleInterestPoolLendingTest is BaseTest {
  address investor1 = makeAddr("INVESTOR_1");
  address minerOwner1 = makeAddr("MINER_OWNER_1");
  string poolName = "TEST 20% Simple Interest Pool";
  uint256 baseInterestRate = 20e18;
  uint256 investor1UnderlyingAmount = 100000e18;
  uint256 borrowAmount = 100000e18;

  IPool4626 simpleInterestPool;
  address miner;
  address loanAgent;
  function setUp() public {
    simpleInterestPool = poolFactory.createSimpleInterestPool(poolName, baseInterestRate);

    vm.deal(investor1, 1000000e18);
    vm.prank(investor1);
    wFIL.deposit{value: 1000000e18}();
    require(wFIL.balanceOf(investor1) == 1000000e18);
    MockMiner _miner;
    ILoanAgent _loanAgent;
    (_loanAgent, _miner) = configureLoanAgent(minerOwner1);
    miner = address(_miner);
    loanAgent = address(_loanAgent);
  }

  function testBorrow() public {
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      uint256 prevMinerBal = wFIL.balanceOf(loanAgent);
      uint256 blockNum = block.number;
      simpleInterestPool.borrow(borrowAmount, loanAgent);
      uint256 postMinerBal = wFIL.balanceOf(loanAgent);

      assertEq(postMinerBal - prevMinerBal, investor1UnderlyingAmount);

      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      assertEq(l.principal, investor1UnderlyingAmount);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount), "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);

      uint256 loanVal = simpleInterestPool.totalLoanValue(l);
      assertEq(l.principal + l.interest, loanVal);
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      assertGt(pmtPerEpoch, 0);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(loanAgent);
      assertEq(loanBalance, 0);
    }

    function testLoanBalance() public {
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      simpleInterestPool.borrow(100000e18, loanAgent);

      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(loanAgent);
      assertEq(loanBalance, 0);

      vm.roll(l.startEpoch + 1);
      (uint256 loanBalanceLater, ) = simpleInterestPool.loanBalance(loanAgent);

      assertEq(loanBalanceLater, pmtPerEpoch);
    }

    function testRepayHalf() public {
      uint256 halfOfBorrowAmount = FixedPointMathLib.divWadDown(borrowAmount, 2e18);
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      simpleInterestPool.borrow(borrowAmount, loanAgent);
      uint256 postLoanMinerBal = wFIL.balanceOf(loanAgent);

      vm.startPrank(loanAgent);
      wFIL.approve(address(simpleInterestPool), halfOfBorrowAmount);
      simpleInterestPool.repay(halfOfBorrowAmount, loanAgent, loanAgent);
      vm.stopPrank();

      uint256 postRepayMinerBal = wFIL.balanceOf(loanAgent);

      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      assertEq(l.principal, investor1UnderlyingAmount);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount));
      assertEq(l.totalPaid, halfOfBorrowAmount);
      assertEq(postLoanMinerBal - postRepayMinerBal, l.totalPaid);
    }

    // function testRepayFull() public {
    //   Loan memory l = simpleInterestPool.getLoan(miner);
    //   assertEq(l.principal, 0);
    //   assertEq(l.interest, 0);
    //   // assertEq(l.periods, simpleInterestPool.loanPeriods());
    //   // assertEq(l.totalPaid, 0.5e18);
    //   // assertEq(postLoanMinerBal - postRepayMinerBal, l.totalPaid);
    //   assertTrue(true);
    // }

    function testMultiBorrow() public {
      uint256 borrowAmount1 = 1000e18;
      uint256 borrowAmount2 = 5000e18;
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      uint256 prevMinerBal = wFIL.balanceOf(loanAgent);
      uint256 blockNum = block.number;
      simpleInterestPool.borrow(borrowAmount1, loanAgent);
      uint256 postMinerBal = wFIL.balanceOf(loanAgent);

      assertEq(postMinerBal - prevMinerBal, borrowAmount1);

      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      assertEq(l.principal, borrowAmount1);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount1), "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);

      uint256 loanVal = simpleInterestPool.totalLoanValue(l);
      assertEq(l.principal + l.interest, loanVal);
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      assertGt(pmtPerEpoch, 0);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(loanAgent);
      assertEq(loanBalance, 0);

      // borrow again
      prevMinerBal = wFIL.balanceOf(loanAgent);
      simpleInterestPool.borrow(borrowAmount2, loanAgent);
      postMinerBal = wFIL.balanceOf(loanAgent);

      assertEq(postMinerBal - prevMinerBal, borrowAmount2, "Miner balance should increase by borrowAmount2");

      uint256 combinedInterest =
        FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount2) + FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount1);

      l = simpleInterestPool.getLoan(loanAgent);
      assertEq(l.principal, borrowAmount1 + borrowAmount2, "Expected principal to increase to include both loan amounts");
      assertEq(l.interest, combinedInterest, "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);
    }

    function testPenalty() public {
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      simpleInterestPool.borrow(100000e18, loanAgent);
      vm.roll(simpleInterestPool.gracePeriod() + 2);

      (uint256 loanBalance, uint256 penalty) = simpleInterestPool.loanBalance(loanAgent);
      assertGt(loanBalance, 0, "Should have non zero balance");
      assertGt(penalty, 0, "Should have non zero penalty.");
    }

    function testSharePricingBeforeRewards() public {
      uint256 sharePrice = simpleInterestPool.convertToAssets(1);

      // deposit into pool
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      assertEq(simpleInterestPool.convertToAssets(1), sharePrice, "Share price should not change upon deposit");

      // borrow from pool
      simpleInterestPool.borrow(10e18, loanAgent);
      // roll blocks forward
      vm.roll(simpleInterestPool.gracePeriod() + 2);

      assertEq(simpleInterestPool.convertToAssets(1), sharePrice, "Share price should not change upon borrow");
    }

    function testSharePricingAfterRewards() public {
      uint256 initialSharePrice = simpleInterestPool.convertToAssets(1);

      // deposit into pool
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      assertEq(simpleInterestPool.convertToAssets(1), initialSharePrice, "Share price should not change upon deposit");

      vm.startPrank(loanAgent);
      // borrow from pool
      simpleInterestPool.borrow(1000e18, loanAgent);
      // give the miner enough funds to pay interest
      vm.deal(loanAgent, 200e18);
      wFIL.deposit{value: 200e18}();
      // pay off entirety of loan + interest immediately
      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      wFIL.approve(address(simpleInterestPool), l.principal + l.interest);

      simpleInterestPool.repay(l.principal + l.interest, loanAgent, loanAgent);

      // since the pool now has a greater asset base than when it did before (interest has been paid), its share price should have increased
      assertGt(simpleInterestPool.convertToAssets(1), initialSharePrice);
    }

    function testLoanBalanceAfterDurationEnds() public {
      // deposit into pool
      vm.startPrank(investor1);
      wFIL.approve(address(simpleInterestPool), investor1UnderlyingAmount);
      simpleInterestPool.deposit(investor1UnderlyingAmount, investor1);
      vm.stopPrank();

      vm.startPrank(loanAgent);
      // borrow from pool
      simpleInterestPool.borrow(1000e18, loanAgent);
      Loan memory l = simpleInterestPool.getLoan(loanAgent);
      // fast forward loanPeriods (so the duration of the loan is technically "over" even though no payments have been made)
      vm.roll(l.startEpoch + simpleInterestPool.loanPeriods() + 1000);
      (uint256 bal, uint256 penalty) = simpleInterestPool.loanBalance(loanAgent);
      // the balance of the loan should be principal + interest
      assertEq(l.principal + l.interest, bal);
      // there should be a penalty
      assertGt(penalty, 0);
    }
}
