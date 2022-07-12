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
    }

    function testChangeOwner() public {
      address bob = address(0x1);
      miner.changeOwnerAddress(bob);
      vm.startPrank(bob);
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

      assertGt(initialAmountLocked, amountLocked1);
      assertGt(amountLocked1, amountLocked2);
      assertEq(noAmountLocked, 0);
    }

    function testWithdrawBalance() public {}
}
