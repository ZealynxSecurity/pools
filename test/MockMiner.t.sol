// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import 'src/Miner/MockMiner.sol';

contract MockMinerTest is Test {
    MockMiner miner;
    function setUp() public {
      miner = new MockMiner();
      payable(address(miner)).transfer(100);
      miner.lockBalance(block.number, 100, 100);
      // make sure the vest is set up right
      assertEq(miner.lockStart(), block.number);
      assertEq(miner.unlockDuration(), 100);
      assertEq(miner.unlockAmount(), 100);
      assertEq(address(miner).balance, 100);
      assertEq(address(this), miner.currentOwner());
    }

    function testChangeOwner() public {
      address bob = address(0x1);
      miner.changeOwnerAddress(bob);
      // become bob
      vm.startPrank(bob);
      // call changeOwnerAddress as bob
      miner.changeOwnerAddress(bob);
      assertEq(bob, miner.currentOwner());
      assertEq(address(0), miner.nextOwner());
    }

    function testAmountLocked() public {
      uint256 initialAmountLocked = miner.amountLocked();
      vm.roll(10);
      uint256 amountLocked1 = miner.amountLocked();
      vm.roll(40);
      uint256 amountLocked2 = miner.amountLocked();
      vm.roll(150);
      uint256 noAmountLocked = miner.amountLocked();

      assertEq(initialAmountLocked, 100);
      assertGt(initialAmountLocked, amountLocked1);
      assertGt(amountLocked1, amountLocked2);
      assertEq(noAmountLocked, 0);
    }

    function testWithdrawBalance() public {
      // here we use a fresh address so we know balances are clean
      address alice = address(0x2);
      require(alice.balance == 0);

      // change the owner so we can withdraw balance to fresh address
      miner.changeOwnerAddress(alice);
      vm.startPrank(alice);
      miner.changeOwnerAddress(alice);

      uint256 initialBalance = alice.balance;
      miner.withdrawBalance(0);
      uint256 withdrawBalance1 = alice.balance;
      assertEq(initialBalance, withdrawBalance1);

      vm.roll(10);

      miner.withdrawBalance(0);
      uint256 withdrawBalance2 = alice.balance;
      assertGt(withdrawBalance2, withdrawBalance1);
    }
}
