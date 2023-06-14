// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MinerHelper} from "shim/MinerHelper.sol";
import {VERSION, IS_FEVM} from "shim/Version.sol";

// used for testing what environments were in
contract Ping {
  event IsOwner(bool);
  event Balance(uint256);
  event AmountWithdrawn(uint256);
  event Received(address, uint256);

  function checkIsOwner(uint64 target) public {
    emit IsOwner(MinerHelper.isOwner(target, address(this)));
  }

  function getBalance(uint64 target) public {
    emit Balance(MinerHelper.balance(target));
  }

  function withdrawBalance(uint64 target, uint256 amount) public {
    uint256 preWithdrawBal = address(this).balance;
    MinerHelper.withdrawBalance(target, amount);
    uint256 postWithdrawBal = address(this).balance;
    emit AmountWithdrawn(postWithdrawBal - preWithdrawBal);
  }

  function transfer(uint64 target, uint256 amount) public {
    MinerHelper.transfer(target, amount);
  }

  function changeOwner(uint64 target) public {
    MinerHelper.changeOwnerAddress(target, address(this));
  }

  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  function getVersion() public pure returns (uint256) {
    return VERSION;
  }

  function getIsFEVM() public pure returns (bool) {
    return IS_FEVM;
  }
}
