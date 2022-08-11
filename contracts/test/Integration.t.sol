// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "./BaseTest.sol";

contract IntegrationTest is BaseTest {
    address investor1 = address(0x10);
    address investor2 = address(0x11);
    address miner1Owner = address(0x20);
    address miner2Owner = address(0x21);
    address treasury = address(0x30);

    string poolName1 = "POOL_1";
    string poolName2 = "POOL_2";
    uint256 poolBaseInterestRate = 20e18;

    MockMiner miner1;
    MockMiner miner2;
    LoanAgentFactory loanAgentFactory;
    LoanAgent loanAgent1;
    LoanAgent loanAgent2;
    WFIL wFil;
    PoolFactory poolFactory;
    IPool4626 pool1;
    IPool4626 pool2;
    function setUp() public {
        vm.label(investor1, "investor1");
        vm.label(investor2, "investor2");
        vm.label(miner1Owner, "miner1Owner");
        vm.label(miner2Owner, "miner2Owner");

        wFil = new WFIL();
        // create 2 pools
        poolFactory = new PoolFactory(wFil, treasury);
        pool1 = poolFactory.createSimpleInterestPool(poolName1, poolBaseInterestRate);
        pool2 = poolFactory.createSimpleInterestPool(poolName2, poolBaseInterestRate);

        // investor1 and investor2 both stake 10 FIL into both pools
        vm.deal(investor1, 100e18);
        vm.deal(investor2, 100e18);
        uint256 stakeAmount = 10e18;

        vm.startPrank(investor1);
        wFil.deposit{value: 100e18}();
        wFil.approve(address(pool1), stakeAmount);
        wFil.approve(address(pool2), stakeAmount);
        pool1.deposit(stakeAmount, investor1);
        pool2.deposit(stakeAmount, investor1);
        vm.stopPrank();

        vm.startPrank(investor2);
        wFil.deposit{value: 100e18}();
        wFil.approve(address(pool1), stakeAmount);
        wFil.approve(address(pool2), stakeAmount);
        pool1.deposit(stakeAmount, investor2);
        pool2.deposit(stakeAmount, investor2);
        vm.stopPrank();

        loanAgentFactory = new LoanAgentFactory(address(poolFactory));

        (miner1, loanAgent1) = setUpMiner(miner1Owner, address(loanAgentFactory));
        (miner2, loanAgent2) = setUpMiner(miner2Owner, address(loanAgentFactory));
    }


    // one miner should be able to take a loan from multiple pools
    function testMultiLoan() public {
      vm.startPrank(miner1Owner);
      uint256 preLoan1Balance = wFil.balanceOf(address(loanAgent1));
      assertEq(preLoan1Balance, 0, "Loan agent pre loan balance should be 0");
      // take a loan from pool 1
      uint256 loanAmount = 1e18;
      loanAgent1.borrow(loanAmount, pool1.id());

      uint256 preLoan2Balance = wFil.balanceOf(address(loanAgent1));
      vm.roll(pool1.getLoan(address(loanAgent1)).startEpoch + 1);
      assertEq(preLoan2Balance, 1e18, "Loan agent balance after loan should be the loanAmount");
      assertEq(pool1.getLoan(address(loanAgent1)).principal, loanAmount);
      assertEq(
        pool1.getLoan(address(loanAgent1)).interest,
        FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            poolBaseInterestRate, 100e18
          ),
          loanAmount
        )
      );
      assertGt(pool1.loanBalance(address(loanAgent1)), 0, "Loan agent's loan balance should be >0 after the start epoch");

      // take a loan from pool 2
      loanAgent1.borrow(loanAmount, pool2.id());
      uint256 currBalance = wFil.balanceOf(address(loanAgent1));
      assertEq(currBalance, loanAmount * 2, "Loan agent's wFIL balance should be two times the loan amount");
      vm.roll(pool2.getLoan(address(loanAgent1)).startEpoch + 1);
      assertEq(preLoan2Balance, 1e18, "Loan agent balance after loan should be the loanAmount");
      assertEq(pool2.getLoan(address(loanAgent1)).principal, loanAmount);
      assertEq(
        pool2.getLoan(address(loanAgent1)).interest,
        FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            poolBaseInterestRate, 100e18
          ),
          loanAmount
        )
      );
      assertGt(pool2.loanBalance(address(loanAgent1)), 0, "Loan agent's loan balance should be >0 after the start epoch");
    }

    // one miner should be able to pay down loans from multiple pools
    function testMultiLoanRepay() public {
      // take out 2 loans for 1 eth each
      vm.startPrank(miner1Owner);
      uint256 loanAmount = 1e18;
      loanAgent1.borrow(loanAmount, pool1.id());
      loanAgent1.borrow(loanAmount, pool2.id());
      assertEq(pool1.getLoan(address(loanAgent1)).principal, loanAmount, "Pool1 loan principal should be equal to the loan amount");
      assertEq(pool2.getLoan(address(loanAgent1)).principal, loanAmount, "Pool2 loan principal should be equal to the loan amount");

      // paydown
      loanAgent1.repay(loanAmount, pool1.id());
      loanAgent1.repay(loanAmount, pool2.id());

      assertEq(pool1.loanBalance(address(loanAgent1)), 0);
      assertEq(pool2.loanBalance(address(loanAgent1)), 0);
    }

    function testGlifFee() public {
      vm.startPrank(miner1Owner);
      uint256 loanAmount = 1e18;
      loanAgent1.borrow(loanAmount, pool1.id());
      loanAgent1.repay(loanAmount, pool1.id());
      pool1.flush();
      assertEq(wFil.balanceOf(treasury), FixedPointMathLib.mulWadDown(
          pool1.fee(),
          loanAmount
        )
      );
    }
}
