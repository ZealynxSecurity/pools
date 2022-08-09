// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "test/BaseTest.sol";

contract IntegrationTest is BaseTest {
    address investor1 = address(0x10);
    address investor2 = address(0x11);
    address miner1Owner = address(0x20);
    address miner2Owner = address(0x21);

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
        poolFactory = new PoolFactory(wFil);
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
      uint256 preLoan1Balance = address(loanAgent1).balance;
      assertEq(preLoan1Balance, 0);
      // take a loan from pool 1
      uint256 loanAmount = 1e18;
      loanAgent1.borrow(loanAmount, pool1.id());
      uint256 preLoan2Balance = address(loanAgent1).balance;
      assertEq(preLoan2Balance, 1e18);
      assertGt(pool1.loanBalance(address(loanAgent1)), 0);

      // take a loan from pool 2
      loanAgent1.borrow(loanAmount, pool2.id());
      uint256 currBalance = address(loanAgent1).balance;
      assertEq(currBalance, loanAmount * 2);
      assertGt(pool2.loanBalance(address(loanAgent1)), 0);

      assertEq(pool1.loanBalance(address(loanAgent1)), pool2.loanBalance(address(loanAgent1)));
    }

    // one miner should be able to pay down loans from multiple pools
    function testMultiLoanPaydown() public {
      // take out 2 loans for 1 eth each
      vm.startPrank(miner1Owner);
      uint256 loanAmount = 1 ether;
      loanAgent1.borrow(loanAmount, pool1.id());
      loanAgent1.borrow(loanAmount, pool2.id());
      assertGt(pool1.loanBalance(address(loanAgent1)), 0);
      assertGt(pool2.loanBalance(address(loanAgent1)), 0);

      // paydown
      // loanAgent1.paydownDebt(loanAmount, pool1.id());
      // loanAgent1.paydownDebt(loanAmount, pool2.id());
      // uint256 p1RepayAmt = pool1.repaymentAmount(loanAmount);
      // uint256 p2RepayAmt = pool2.repaymentAmount(loanAmount);
      // assertEq(pool1.loanBalance(address(loanAgent1)), p1RepayAmt - loanAmount);
      // assertEq(pool2.loanBalance(address(loanAgent1)), p2RepayAmt - loanAmount);
    }
}
