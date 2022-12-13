// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Agent/Agent.sol";
import "src/Agent/AgentFactory.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "./BaseTest.sol";

contract IntegrationTest is BaseTest {
    address investor1 = makeAddr('INVESTOR_1');
    address investor2 = makeAddr('INVESTOR_2');
    address minerOwner1 = makeAddr('MINER_OWNER_1');
    address minerOwner2 = makeAddr('MINER_OWNER_2');

    string poolName1 = "POOL_1";
    string poolName2 = "POOL_2";
    uint256 poolBaseInterestRate = 20e18;

    MockMiner miner1;
    MockMiner miner2;
    Agent agent1;
    Agent agent2;
    IPool4626 pool1;
    IPool4626 pool2;
    function setUp() public {
      // create 2 pools
      pool1 = poolFactory.createSimpleInterestPool(poolName1, poolBaseInterestRate);
      pool2 = poolFactory.createSimpleInterestPool(poolName2, poolBaseInterestRate);

      // investor1 and investor2 both stake 10 FIL into both pools
      vm.deal(investor1, 100e18);
      vm.deal(investor2, 100e18);
      uint256 stakeAmount = 10e18;

      vm.startPrank(investor1);
      wFIL.deposit{value: 100e18}();
      wFIL.approve(address(pool1), stakeAmount);
      wFIL.approve(address(pool2), stakeAmount);
      pool1.deposit(stakeAmount, investor1);
      pool2.deposit(stakeAmount, investor1);
      vm.stopPrank();

      vm.startPrank(investor2);
      wFIL.deposit{value: 100e18}();
      wFIL.approve(address(pool1), stakeAmount);
      wFIL.approve(address(pool2), stakeAmount);
      pool1.deposit(stakeAmount, investor2);
      pool2.deposit(stakeAmount, investor2);
      vm.stopPrank();

      (agent1, miner1) = configureAgent(minerOwner1);
      (agent2, miner2) = configureAgent(minerOwner2);
    }


    // one miner should be able to take a loan from multiple pools
    function testMultiLoan() public {
      vm.startPrank(minerOwner1);
      uint256 preLoan1Balance = wFIL.balanceOf(address(agent1));
      assertEq(preLoan1Balance, 0, "Loan agent pre loan balance should be 0");
      // take a loan from pool 1
      uint256 loanAmount = 1e18;
      agent1.borrow(loanAmount, pool1.id());

      uint256 preLoan2Balance = wFIL.balanceOf(address(agent1));
      vm.roll(pool1.getLoan(address(agent1)).startEpoch + 1);
      assertEq(preLoan2Balance, 1e18, "Loan agent balance after loan should be the loanAmount");
      assertEq(pool1.getLoan(address(agent1)).principal, loanAmount);
      assertEq(
        pool1.getLoan(address(agent1)).interest,
        FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            poolBaseInterestRate, 100e18
          ),
          loanAmount
        )
      );
      (uint256 bal, ) = pool1.loanBalance(address(agent1));
      assertGt(bal, 0, "Agent's loan balance should be >0 after the start epoch");

      // take a loan from pool 2
      agent1.borrow(loanAmount, pool2.id());
      uint256 currBalance = wFIL.balanceOf(address(agent1));
      assertEq(currBalance, loanAmount * 2, "Agent's wFIL balance should be two times the loan amount");
      vm.roll(pool2.getLoan(address(agent1)).startEpoch + 1);
      assertEq(preLoan2Balance, 1e18, "Agent balance after loan should be the loanAmount");
      assertEq(pool2.getLoan(address(agent1)).principal, loanAmount);
      assertEq(
        pool2.getLoan(address(agent1)).interest,
        FixedPointMathLib.mulWadDown(
          FixedPointMathLib.divWadDown(
            poolBaseInterestRate, 100e18
          ),
          loanAmount
        )
      );
      (uint256 bal2, ) = pool2.loanBalance(address(agent1));
      assertGt(bal2, 0, "Agent's loan balance should be >0 after the start epoch");
    }

    // one miner should be able to pay down loans from multiple pools
    function testMultiLoanRepay() public {
      // take out 2 loans for 1 eth each
      vm.startPrank(minerOwner1);
      uint256 loanAmount = 1e18;
      agent1.borrow(loanAmount, pool1.id());
      agent1.borrow(loanAmount, pool2.id());
      assertEq(pool1.getLoan(address(agent1)).principal, loanAmount, "Pool1 loan principal should be equal to the loan amount");
      assertEq(pool2.getLoan(address(agent1)).principal, loanAmount, "Pool2 loan principal should be equal to the loan amount");

      // paydown
      agent1.repay(loanAmount, pool1.id());
      agent1.repay(loanAmount, pool2.id());

      (uint256 bal1, ) = pool1.loanBalance(address(agent1));
      (uint256 bal2, ) = pool2.loanBalance(address(agent1));
      assertEq(bal1, 0);
      assertEq(bal2, 0);
    }

    function testGlifFee() public {
      vm.startPrank(minerOwner1);
      uint256 loanAmount = 1e18;
      agent1.borrow(loanAmount, pool1.id());
      agent1.repay(loanAmount, pool1.id());
      pool1.flush();
      assertEq(wFIL.balanceOf(treasury), FixedPointMathLib.mulWadDown(
          pool1.fee(),
          loanAmount
        )
      );
    }
}
