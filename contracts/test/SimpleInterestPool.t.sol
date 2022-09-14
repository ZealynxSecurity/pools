// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Pool/SimpleInterestPool.sol";
import "src/WFIL.sol";

contract SimpleInterestPoolStakingTest is Test {
  address alice = address(0xABCD);
  address treasury = address(0x30);
  string poolName = "TEST 20% Simple Interest Pool";
  string poolSymbol = "p0GCRED";

  WFIL wFil;
  IPool4626 simpleInterestPool;
  function setUp() public {
    wFil = new WFIL();
    simpleInterestPool = new SimpleInterestPool(wFil, poolName, poolSymbol, 0, 20e18, treasury);

    vm.deal(alice, 10e18);
    vm.prank(alice);
    wFil.deposit{value: 1e18}();
    require(wFil.balanceOf(alice) == 1e18);
  }

  function testAsset() public {
    ERC20 asset = simpleInterestPool.asset();
    assertEq(asset.name(), "Wrapped Filecoin");
    assertEq(asset.symbol(), "WFIL");
    assertEq(asset.decimals(), 18);
  }

  function testPoolToken() public {
    assertEq(simpleInterestPool.name(), poolName);
    assertEq(simpleInterestPool.symbol(), poolSymbol);
    assertEq(simpleInterestPool.decimals(), 18);
  }

  function testSingleDepositWithdraw() public {
    uint256 aliceUnderlyingAmount = 1e18;

    vm.prank(alice);
    wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
    assertEq(wFil.allowance(alice, address(simpleInterestPool)), aliceUnderlyingAmount);

    uint256 alicePreDepositBal = wFil.balanceOf(alice);

    vm.prank(alice);
    uint256 aliceShareAmount = simpleInterestPool.deposit(aliceUnderlyingAmount, alice);

    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(aliceUnderlyingAmount, aliceShareAmount);
    assertEq(simpleInterestPool.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    assertEq(simpleInterestPool.totalSupply(), aliceShareAmount);
    assertEq(simpleInterestPool.totalAssets(), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(alice), aliceShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(alice)), aliceUnderlyingAmount);
    assertEq(wFil.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    vm.prank(alice);
    simpleInterestPool.withdraw(aliceUnderlyingAmount, alice, alice);

    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(alice), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(alice)), 0);
    assertEq(wFil.balanceOf(alice), alicePreDepositBal);
  }

  function testSingleMintRedeem() public {
    uint256 aliceShareAmount = 1e18;

    vm.prank(alice);
    wFil.approve(address(simpleInterestPool), aliceShareAmount);
    assertEq(wFil.allowance(alice, address(simpleInterestPool)), aliceShareAmount);

    uint256 alicePreDepositBal = wFil.balanceOf(alice);

    vm.prank(alice);
    uint256 aliceUnderlyingAmount = simpleInterestPool.mint(aliceShareAmount, alice);

    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(aliceShareAmount, aliceUnderlyingAmount);
    assertEq(simpleInterestPool.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    assertEq(simpleInterestPool.totalSupply(), aliceShareAmount);
    assertEq(simpleInterestPool.totalAssets(), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(alice), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(alice)), aliceUnderlyingAmount);
    assertEq(wFil.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    vm.prank(alice);
    simpleInterestPool.redeem(aliceShareAmount, alice, alice);

    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(alice), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(alice)), 0);
    assertEq(wFil.balanceOf(alice), alicePreDepositBal);
  }

  function testMultipleMintDepositRedeemWithdraw() public {
    address rewardsActor = address(0xAAAA);
    vm.deal(rewardsActor, 10 ether);
    vm.prank(rewardsActor);
    wFil.deposit{value: 10 ether}();

    // Scenario:
    // A = Arthur, B = Bob
    //  ________________________________________________________
    // | Pool shares | A share | A assets | B share | B assets |
    // |========================================================|
    // | 1. Arthur mints 2000 shares (costs 2000 tokens)         |
    // |--------------|---------|----------|---------|----------|
    // |         2000 |    2000 |     2000 |       0 |        0 |
    // |--------------|---------|----------|---------|----------|
    // | 2. Bob deposits 4000 tokens (mints 4000 shares)        |
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
    // | 5. Bob mints 2000 shares (costs 3001 assets)           |
    // |    NOTE: Bob's assets spent got rounded up             |
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
    // | 8. Bob withdraws 2928 assets (1608 shares)             |
    // |--------------|---------|----------|---------|----------|
    // |         6392 |    2000 |     3643 |    4392 |     8000 |
    // |--------------|---------|----------|---------|----------|
    // | 9. Arthur withdraws 3643 assets (2000 shares)           |
    // |    NOTE: Bob's assets have been rounded back up        |
    // |--------------|---------|----------|---------|----------|
    // |         4392 |       0 |        0 |    4392 |     8001 |
    // |--------------|---------|----------|---------|----------|
    // | 10. Bob redeem 4392 shares (8001 tokens)               |
    // |--------------|---------|----------|---------|----------|
    // |            0 |       0 |        0 |       0 |        0 |
    // |______________|_________|__________|_________|__________|

    address arthur = address(0xBADC);
    address bob = address(0xDCBA);
    vm.deal(arthur, 1e18);
    vm.deal(bob, 1e18);

    uint256 mutationUnderlyingAmount = 3000;


    vm.startPrank(arthur);
    wFil.deposit{value: 4000}();

    wFil.approve(address(simpleInterestPool), 4000);
    vm.stopPrank();

    assertEq(wFil.allowance(arthur, address(simpleInterestPool)), 4000);

    vm.startPrank(bob);
    wFil.deposit{value: 7001}();
    wFil.approve(address(simpleInterestPool), 7001);
    vm.stopPrank();

    assertEq(wFil.allowance(bob, address(simpleInterestPool)), 7001);

    // 1. Arthur mints 2000 shares (costs 2000 tokens)
    vm.prank(arthur);
    uint256 aliceUnderlyingAmount = simpleInterestPool.mint(2000, arthur);

    uint256 aliceShareAmount = simpleInterestPool.previewDeposit(aliceUnderlyingAmount);

    // Expect to have received the requested mint amount.
    assertEq(aliceShareAmount, 2000);
    assertEq(simpleInterestPool.balanceOf(arthur), aliceShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), aliceUnderlyingAmount);
    assertEq(simpleInterestPool.convertToShares(aliceUnderlyingAmount), simpleInterestPool.balanceOf(arthur));

    // Expect a 1:1 ratio before mutation.
    assertEq(aliceUnderlyingAmount, 2000);

    // Sanity check.
    assertEq(simpleInterestPool.totalSupply(), aliceShareAmount);
    assertEq(simpleInterestPool.totalAssets(), aliceUnderlyingAmount);

    // 2. Bob deposits 4000 tokens (mints 4000 shares)
    vm.prank(bob);
    uint256 bobShareAmount = simpleInterestPool.deposit(4000, bob);
    uint256 bobUnderlyingAmount = simpleInterestPool.previewWithdraw(bobShareAmount);

    // Expect to have received the requested wFil amount.
    assertEq(bobUnderlyingAmount, 4000);
    assertEq(simpleInterestPool.balanceOf(bob), bobShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), bobUnderlyingAmount);
    assertEq(simpleInterestPool.convertToShares(bobUnderlyingAmount), simpleInterestPool.balanceOf(bob));

    // Expect a 1:1 ratio before mutation.
    assertEq(bobShareAmount, bobUnderlyingAmount);

    // Sanity check.
    uint256 preMutationShareBal = aliceShareAmount + bobShareAmount;
    uint256 preMutationBal = aliceUnderlyingAmount + bobUnderlyingAmount;
    assertEq(simpleInterestPool.totalSupply(), preMutationShareBal);
    assertEq(simpleInterestPool.totalAssets(), preMutationBal);
    assertEq(simpleInterestPool.totalSupply(), 6000);
    assertEq(simpleInterestPool.totalAssets(), 6000);

    // 3. Pool mutates by +3000 tokens...                    |
    //    (simulated yield returned from strategy)...
    // The Pool now contains more tokens than deposited which causes the exchange rate to change.
    // Arthur share is 33.33% of the Pool, Bob 66.66% of the Pool.
    // Arthur's share count stays the same but the wFil amount changes from 2000 to 3000.
    // Bob's share count stays the same but the wFil amount changes from 4000 to 6000.
    vm.prank(rewardsActor);
    wFil.transfer(address(simpleInterestPool), mutationUnderlyingAmount);

    assertEq(simpleInterestPool.totalSupply(), preMutationShareBal);
    assertEq(simpleInterestPool.totalAssets(), preMutationBal + mutationUnderlyingAmount);
    assertEq(simpleInterestPool.balanceOf(arthur), aliceShareAmount);
    assertEq(
        simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)),
        aliceUnderlyingAmount + (mutationUnderlyingAmount / 3) * 1
    );
    assertEq(simpleInterestPool.balanceOf(bob), bobShareAmount);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), bobUnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

    // 4. Alice deposits 2000 tokens (mints 1333 shares)
    vm.prank(arthur);
    simpleInterestPool.deposit(2000, arthur);

    assertEq(simpleInterestPool.totalSupply(), 7333);
    assertEq(simpleInterestPool.balanceOf(arthur), 3333);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 4999);
    assertEq(simpleInterestPool.balanceOf(bob), 4000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 6000);

    // 5. Bob mints 2000 shares (costs 3001 assets)
    // NOTE: Bob's assets spent got rounded up
    // NOTE: Alices's simpleInterestPool assets got rounded up
    vm.prank(bob);
    simpleInterestPool.mint(2000, bob);

    assertEq(simpleInterestPool.totalSupply(), 9333);
    assertEq(simpleInterestPool.balanceOf(arthur), 3333);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 5000);
    assertEq(simpleInterestPool.balanceOf(bob), 6000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 9000);

    // Sanity checks:
    // Alice and bob should have spent all their tokens now
    assertEq(wFil.balanceOf(arthur), 0);
    assertEq(wFil.balanceOf(bob), 0);
    // Assets in simpleInterestPool: 4k (arthur) + 7k (bob) + 3k (yield) + 1 (round up)
    assertEq(simpleInterestPool.totalAssets(), 14001);

    // 6. Vault mutates by +3000 tokens
    // NOTE: Vault holds 17001 tokens, but sum of assetsOf() is 17000.
    vm.prank(rewardsActor);
    wFil.transfer(address(simpleInterestPool), mutationUnderlyingAmount);
    assertEq(simpleInterestPool.totalAssets(), 17001);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 6071);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 10929);

    // 7. Alice redeem 1333 shares (2428 assets)
    vm.prank(arthur);
    simpleInterestPool.redeem(1333, arthur, arthur);

    assertEq(wFil.balanceOf(arthur), 2428);
    assertEq(simpleInterestPool.totalSupply(), 8000);
    assertEq(simpleInterestPool.totalAssets(), 14573);
    assertEq(simpleInterestPool.balanceOf(arthur), 2000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 3643);
    assertEq(simpleInterestPool.balanceOf(bob), 6000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 10929);

    // 8. Bob withdraws 2929 assets (1608 shares)
    vm.prank(bob);
    simpleInterestPool.withdraw(2929, bob, bob);

    assertEq(wFil.balanceOf(bob), 2929);
    assertEq(simpleInterestPool.totalSupply(), 6392);
    assertEq(simpleInterestPool.totalAssets(), 11644);
    assertEq(simpleInterestPool.balanceOf(arthur), 2000);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 3643);
    assertEq(simpleInterestPool.balanceOf(bob), 4392);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 8000);

    // 9. Alice withdraws 3643 assets (2000 shares)
    // NOTE: Bob's assets have been rounded back up
    vm.prank(arthur);
    simpleInterestPool.withdraw(3643, arthur, arthur);

    assertEq(wFil.balanceOf(arthur), 6071);
    assertEq(simpleInterestPool.totalSupply(), 4392);
    assertEq(simpleInterestPool.totalAssets(), 8001);
    assertEq(simpleInterestPool.balanceOf(arthur), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 0);
    assertEq(simpleInterestPool.balanceOf(bob), 4392);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 8001);

    // 10. Bob redeem 4392 shares (8001 tokens)
    vm.prank(bob);
    simpleInterestPool.redeem(4392, bob, bob);
    assertEq(wFil.balanceOf(bob), 10930);
    assertEq(simpleInterestPool.totalSupply(), 0);
    assertEq(simpleInterestPool.totalAssets(), 0);
    assertEq(simpleInterestPool.balanceOf(arthur), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(arthur)), 0);
    assertEq(simpleInterestPool.balanceOf(bob), 0);
    assertEq(simpleInterestPool.convertToAssets(simpleInterestPool.balanceOf(bob)), 0);

    // Sanity check
    assertEq(wFil.balanceOf(address(simpleInterestPool)), 0);
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
        wFil.deposit{value: 0.5e18}();
        wFil.approve(address(simpleInterestPool), 0.5e18);
        assertEq(wFil.allowance(address(this), address(simpleInterestPool)), 0.5e18);

        simpleInterestPool.deposit(1e18, address(this));
    }

    function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
        wFil.deposit{value: 0.5e18}();
        wFil.approve(address(simpleInterestPool), 0.5e18);

        simpleInterestPool.deposit(0.5e18, address(this));

        simpleInterestPool.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughShareAmount() public {
        wFil.deposit{value: 0.5e18}();
        wFil.approve(address(simpleInterestPool), 0.5e18);

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

contract SimpleInterestPoolLendingTest is Test {
  address alice = address(0xABCD);
  address miner = address(0xCCCC);
  address treasury = address(0x30);

  string poolName = "TEST 20% Simple Interest Pool";
  string poolSymbol = "p0GCRED";
  uint256 interestBaseRate = 20e18;
  uint256 aliceUnderlyingAmount = 100000e18;
  uint256 borrowAmount = 100000e18;

  WFIL wFil;
  IPool4626 simpleInterestPool;
  function setUp() public {
    wFil = new WFIL();
    simpleInterestPool = new SimpleInterestPool(wFil, poolName, poolSymbol, 0, interestBaseRate, treasury);

    vm.deal(alice, 1000000e18);
    vm.prank(alice);
    wFil.deposit{value: 1000000e18}();
    require(wFil.balanceOf(alice) == 1000000e18);
  }

  function testBorrow() public {
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      uint256 prevMinerBal = wFil.balanceOf(miner);
      uint256 blockNum = block.number;
      simpleInterestPool.borrow(borrowAmount, miner);
      uint256 postMinerBal = wFil.balanceOf(miner);

      assertEq(postMinerBal - prevMinerBal, aliceUnderlyingAmount);

      Loan memory l = simpleInterestPool.getLoan(address(miner));
      assertEq(l.principal, aliceUnderlyingAmount);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount), "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);

      uint256 loanVal = simpleInterestPool.totalLoanValue(l);
      assertEq(l.principal + l.interest, loanVal);
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      assertGt(pmtPerEpoch, 0);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(address(miner));
      assertEq(loanBalance, 0);
    }

    function testLoanBalance() public {
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      simpleInterestPool.borrow(100000e18, miner);

      Loan memory l = simpleInterestPool.getLoan(address(miner));
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(address(miner));
      assertEq(loanBalance, 0);

      vm.roll(l.startEpoch + 1);
      (uint256 loanBalanceLater, ) = simpleInterestPool.loanBalance(address(miner));

      assertEq(loanBalanceLater, pmtPerEpoch);
    }

    function testRepayHalf() public {
      uint256 halfOfBorrowAmount = FixedPointMathLib.divWadDown(borrowAmount, 2e18);
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      simpleInterestPool.borrow(borrowAmount, miner);
      uint256 postLoanMinerBal = wFil.balanceOf(miner);

      vm.startPrank(miner);
      wFil.approve(address(simpleInterestPool), halfOfBorrowAmount);
      simpleInterestPool.repay(halfOfBorrowAmount, miner, miner);
      vm.stopPrank();

      uint256 postRepayMinerBal = wFil.balanceOf(miner);

      Loan memory l = simpleInterestPool.getLoan(address(miner));
      assertEq(l.principal, aliceUnderlyingAmount);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount));
      assertEq(l.totalPaid, halfOfBorrowAmount);
      assertEq(postLoanMinerBal - postRepayMinerBal, l.totalPaid);
    }

    // function testRepayFull() public {
    //   Loan memory l = simpleInterestPool.getLoan(address(miner));
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
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      uint256 prevMinerBal = wFil.balanceOf(miner);
      uint256 blockNum = block.number;
      simpleInterestPool.borrow(borrowAmount1, miner);
      uint256 postMinerBal = wFil.balanceOf(miner);

      assertEq(postMinerBal - prevMinerBal, borrowAmount1);

      Loan memory l = simpleInterestPool.getLoan(address(miner));
      assertEq(l.principal, borrowAmount1);
      assertEq(l.interest, FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount1), "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);

      uint256 loanVal = simpleInterestPool.totalLoanValue(l);
      assertEq(l.principal + l.interest, loanVal);
      uint256 pmtPerEpoch = simpleInterestPool.pmtPerEpoch(l);
      assertGt(pmtPerEpoch, 0);
      (uint256 loanBalance, ) = simpleInterestPool.loanBalance(address(miner));
      assertEq(loanBalance, 0);

      // borrow again
      prevMinerBal = wFil.balanceOf(miner);
      simpleInterestPool.borrow(borrowAmount2, miner);
      postMinerBal = wFil.balanceOf(miner);

      assertEq(postMinerBal - prevMinerBal, borrowAmount2, "Miner balance should increase by borrowAmount2");

      uint256 combinedInterest =
        FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount2) + FixedPointMathLib.mulWadDown(simpleInterestPool.interestRate(), borrowAmount1);

      l = simpleInterestPool.getLoan(address(miner));
      assertEq(l.principal, borrowAmount1 + borrowAmount2, "Expected principal to increase to include both loan amounts");
      assertEq(l.interest, combinedInterest, "it should report the correct interest amount owed on the loan");
      assertEq(l.totalPaid, 0);
      assertEq(l.startEpoch, blockNum);
    }

    function testPenalty() public {
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      simpleInterestPool.borrow(100000e18, miner);
      vm.roll(simpleInterestPool.gracePeriod() + 2);

      (uint256 loanBalance, uint256 penalty) = simpleInterestPool.loanBalance(address(miner));
      assertGt(loanBalance, 0, "Should have non zero balance");
      assertGt(penalty, 0, "Should have non zero penalty.");
    }

    function testSharePricingBeforeRewards() public {
      uint256 sharePrice = simpleInterestPool.convertToAssets(1);

      // deposit into pool
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      assertEq(simpleInterestPool.convertToAssets(1), sharePrice, "Share price should not change upon deposit");

      // borrow from pool
      simpleInterestPool.borrow(10e18, miner);
      // roll blocks forward
      vm.roll(simpleInterestPool.gracePeriod() + 2);

      assertEq(simpleInterestPool.convertToAssets(1), sharePrice, "Share price should not change upon borrow");
    }

    function testSharePricingAfterRewards() public {
      uint256 initialSharePrice = simpleInterestPool.convertToAssets(1);

      // deposit into pool
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      assertEq(simpleInterestPool.convertToAssets(1), initialSharePrice, "Share price should not change upon deposit");

      vm.startPrank(miner);
      // borrow from pool
      simpleInterestPool.borrow(1000e18, miner);
      // give the miner enough funds to pay interest
      vm.deal(address(miner), 200e18);
      wFil.deposit{value: 200e18}();
      // pay off entirety of loan + interest immediately
      Loan memory l = simpleInterestPool.getLoan(address (miner));
      wFil.approve(address(simpleInterestPool), l.principal + l.interest);

      simpleInterestPool.repay(l.principal + l.interest, address(miner), address(miner));

      // since the pool now has a greater asset base than when it did before (interest has been paid), its share price should have increased
      assertGt(simpleInterestPool.convertToAssets(1), initialSharePrice);
    }

    function testLoanBalanceAfterDurationEnds() public {
      // deposit into pool
      vm.startPrank(alice);
      wFil.approve(address(simpleInterestPool), aliceUnderlyingAmount);
      simpleInterestPool.deposit(aliceUnderlyingAmount, alice);
      vm.stopPrank();

      vm.startPrank(miner);
      // borrow from pool
      simpleInterestPool.borrow(1000e18, miner);
      Loan memory l = simpleInterestPool.getLoan(address(miner));
      // fast forward loanPeriods (so the duration of the loan is technically "over" even though no payments have been made)
      vm.roll(l.startEpoch + simpleInterestPool.loanPeriods() + 1000);
      (uint256 bal, uint256 penalty) = simpleInterestPool.loanBalance(address(miner));
      // the balance of the loan should be principal + interest
      assertEq(l.principal + l.interest, bal);
      // there should be a penalty
      assertGt(penalty, 0);
    }
}
