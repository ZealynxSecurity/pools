// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import "src/Pool.sol";
import "src/LoanAgent/ILoanAgent.sol";

contract LoanAgent is ILoanAgent {
  address public miner;
  address public owner;
  address public pool;
  bool public active = false;

  constructor(address _miner, address _pool) {
    miner = _miner;
    pool = _pool;
  }

  receive() external payable {}

  // this function does two things:
  // 1. it sets the miner's owner addr to be the loan agent
  // 2. it sets the loan agent's owner to be the old miner owner
  // only the miner's current owner can claim ownership over that miner's loan agent
  function claimOwnership() external {
    // TODO: needs a solution for FVM <> EVM compatibility
    require(IMiner(miner).nextOwner() == address(this));
    require(IMiner(miner).currentOwner() == msg.sender);
    IMiner(miner).changeOwnerAddress(address(this));
    // if this call does not error out, set the owner of this loan agent to be the sender of this message
    owner = msg.sender;
    active = true;
  }

  // TODO: should not allow ownership revocation if active loans exist for this loan agent
  function revokeMinerOwnership(address newOwner) external {
    require(owner == msg.sender, "Only LoanAgent owner can call revokeOwnership");
    require(IMiner(miner).currentOwner() == address(this), "LoanAgent does not own miner");

    IMiner(miner).changeOwnerAddress(newOwner);
    active = false;
  }

  function withdrawBalance() external returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  function takeLoan(uint256 amount) external returns (uint256) {
    return IPool(pool).takeLoan(amount);
  }

  function paydownDebt() external returns (uint256) {
    return IPool(pool).paydownDebt{value: address(this).balance}(address(this));
  }
}

