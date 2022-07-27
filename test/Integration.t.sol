// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/Pool/Pool.sol";
import "src/Pool/PoolFactory.sol";

contract BaseTest is Test {
  function setUpMiner(address _owner, address _loanAgentFactory) public returns (MockMiner, LoanAgent) {
      // create 2 miners and assign them each a loan agent
      vm.startPrank(_owner);
      MockMiner miner = new MockMiner();
      // give miner some fake rewards
      vm.deal(address(miner), 100 ether);
      miner.lockBalance(block.number, 100, 100 ether);
      // create a loan agent for miner
      LoanAgent loanAgent = LoanAgent(
        payable(
          ILoanAgentFactory(_loanAgentFactory).create(address(miner))
        ));
      // propose the change owner to the loan agent
      miner.changeOwnerAddress(address(loanAgent));
      // confirm change owner address (loanAgent1 now owns miner)
      loanAgent.claimOwnership();

      require(miner.currentOwner() == address(loanAgent));
      require(loanAgent.owner() == _owner);
      require(loanAgent.miner() == address(miner));

      vm.stopPrank();
      return (miner, loanAgent);
  }
}

contract IntegrationTest is BaseTest {
    address investor1 = address(0x10);
    address investor2 = address(0x11);
    address miner1Owner = address(0x20);
    address miner2Owner = address(0x21);

    string poolName1 = "POOL_1";
    string poolName2 = "POOL_2";

    MockMiner miner1;
    MockMiner miner2;
    LoanAgentFactory loanAgentFactory;
    LoanAgent loanAgent1;
    LoanAgent loanAgent2;
    PoolFactory poolFactory;
    Pool pool1;
    Pool pool2;
    function setUp() public {
        vm.label(investor1, "investor1");
        vm.label(investor2, "investor2");
        vm.label(miner1Owner, "miner1Owner");
        vm.label(miner2Owner, "miner2Owner");

        // create 2 pools
        poolFactory = new PoolFactory();
        pool1 = new Pool(1 ether, poolName1);
        pool2 = new Pool(1 ether, poolName2);
        poolFactory.create(address(pool1));
        poolFactory.create(address(pool2));

        // investor1 and investor2 both stake 10 FIL into both pools
        vm.deal(investor1, 100 ether);
        vm.deal(investor2, 100 ether);
        uint256 stakeAmount = 10 ether;

        vm.startPrank(investor1);
        pool1.stake{value: stakeAmount}(investor1);
        pool2.stake{value: stakeAmount}(investor1);
        vm.stopPrank();

        vm.startPrank(investor2);
        pool1.stake{value: stakeAmount}(investor2);
        pool2.stake{value: stakeAmount}(investor2);
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
      uint256 loanAmount = 1 ether;
      loanAgent1.takeLoan(loanAmount, pool1.id());
      uint256 preLoan2Balance = address(loanAgent1).balance;
      assertEq(preLoan2Balance, 1 ether);
      assertGt(pool1._loans(address(loanAgent1)), 0);

      // take a loan from pool 2
      loanAgent1.takeLoan(loanAmount, pool2.id());
      uint256 currBalance = address(loanAgent1).balance;
      assertEq(currBalance, loanAmount * 2);
      assertGt(pool2._loans(address(loanAgent1)), 0);

      assertEq(pool1._loans(address(loanAgent1)), pool2._loans(address(loanAgent1)));
    }

    // one miner should be able to pay down loans from multiple pools
    function testMultiLoanPaydown() public {
      assertTrue(true);
    }
}
