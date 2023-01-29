// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IMockMiner} from "src/Types/Interfaces/IMockMiner.sol";
import {
  ChangeWorkerAddressParams,
  ChangePeerIDParams,
  ChangeMultiaddrsParams
} from "src/Types/Structs/Filecoin.sol";

contract MockMiner is IMockMiner {
  address private _get_owner;
  address private _get_beneficiary;
  address private _next_owner;
  uint256 public lockStart;
  uint256 public unlockDuration;
  uint256 public unlockAmount;
  uint256 public pledgedAmount;

  constructor() payable {
    _get_owner = msg.sender;
  }

  receive() external payable {}

  fallback() external payable {}

  function get_owner(address) external view returns (address) {
    return _get_owner;
  }

  function get_beneficiary(address) external view returns (address) {
    return _get_beneficiary;
  }

  function next_owner(address) external view returns (address) {
    return _next_owner;
  }

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
    require(msg.sender == _get_owner);
    require(unlockAmount <= address(this).balance);
    lockStart = _lockStart;
    unlockDuration = _unlockDuration;
    unlockAmount = _unlockAmount;
  }

  function change_owner_address(address, address newOwner) external {
    if (msg.sender == _get_owner) {
      _next_owner = newOwner;
    } else if (msg.sender == _next_owner && newOwner == _next_owner) {
      _get_owner = _next_owner;
      _next_owner = address(0);
    } else {
      revert("not authorized");
    }
  }

  function withdrawBalance(uint256 amountRequested) external returns (uint256 amount) {
    // check
    require(msg.sender == _get_owner);
    uint256 bal = address(this).balance;
    uint256 maxSend = bal - amountLocked();
    require(amountRequested <= maxSend);

    // effect
    if (amountRequested == 0) {
      amount = maxSend;
    } else {
      amount = amountRequested;
    }

    // interact
    (bool success, ) = payable(address(_get_owner)).call{value: amount}("");
    require(success, "transfer failed");
  }

  // used for pledging collateral
  function applyRewards(uint256 reward, uint256 penalty) external {
    pledgedAmount += reward;
    pledgedAmount -= penalty;
  }

  function change_worker_address(
    address miner,
    ChangeWorkerAddressParams memory params
  ) external {}

  function change_peer_id(
    address miner,
    ChangePeerIDParams memory params
  ) external {}

  function change_multiaddresses(
    address miner,
    ChangeMultiaddrsParams memory params
  ) external {}
}
