// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {MinerHelper} from "helpers/MinerHelper.sol";

contract MinerHelperTester {
  event IsOwner(bool);

  function checkIsOwner(uint64 target) public {
    emit IsOwner(MinerHelper.isOwner(target, address(this)));
  }

  event Balance(uint256);

  function getBalance(uint64 target) public {
    emit Balance(MinerHelper.balance(target));
  }

  event AmountWithdrawn(uint256);

  function withdrawBalance(uint64 target, uint256 amount) public {
    uint256 amountWithdrawn = MinerHelper.withdrawBalance(target, amount);
    emit AmountWithdrawn(amountWithdrawn);
  }

  function transfer(uint64 target, uint256 amount) public {
    MinerHelper.transfer(target, amount);
  }

  function changeOwner(uint64 target) public {
    MinerHelper.changeOwnerAddress(target, address(this));
  }

  event Received(address, uint256);

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }
}
