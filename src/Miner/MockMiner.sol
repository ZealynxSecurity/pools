// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./IMiner.sol";

contract MockMiner is IMiner {
  address public currentOwner;
  address public nextOwner;
  uint256 public lockStart;
  uint256 public unlockDuration;
  uint256 public unlockAmount;
  uint256 public pledgedAmount;

  constructor() payable {
    currentOwner = msg.sender;
  }

  receive() external payable {}

  function amountLocked() public view returns (uint256) {
    uint256 elapsedBlocks = block.number - lockStart;
    if (elapsedBlocks >= unlockDuration) {
      return 0;
    }
    if  (elapsedBlocks <=  0) {
      return unlockAmount;
    }

    // locked = ceil(InitialBalance * remainingLockDuration / UnlockDuration)
    uint256 remainingUnlockDuration = unlockDuration - elapsedBlocks;
    uint256 balance = address(this).balance;
    uint256 numerator = balance * remainingUnlockDuration;
    return numerator / unlockDuration;
  }

  function lockBalance(uint256 _lockStart, uint256 _unlockDuration,  uint256 _unlockAmount) external {
    require(msg.sender == currentOwner);
    require(unlockAmount <= address(this).balance);
    lockStart = _lockStart;
    unlockDuration = _unlockDuration;
    unlockAmount = _unlockAmount;
  }

  function changeOwnerAddress(address newOwner) external {
    if (msg.sender == currentOwner) {
      nextOwner = newOwner;
    } else if (msg.sender == nextOwner && newOwner == nextOwner) {
      currentOwner = nextOwner;
      nextOwner = address(0);
    }
  }

  function withdrawBalance(uint256 amountRequested) external returns (uint256) {
    require(msg.sender == currentOwner);
    uint256 bal = address(this).balance;
    uint256 maxSend = bal - amountLocked();
    require(amountRequested <= maxSend);
    if (amountRequested == 0) {
      payable(address(currentOwner)).transfer(maxSend);
      return maxSend;
    } else {
      payable(address(currentOwner)).transfer(amountRequested);
      return amountRequested;
    }
  }

  // used for pledging collateral
  function applyRewards(uint256 reward, uint256 penalty) external {
    pledgedAmount += reward;
    pledgedAmount -= penalty;
  }
}
