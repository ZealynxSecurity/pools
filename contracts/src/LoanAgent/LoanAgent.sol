// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import "src/LoanAgent/ILoanAgent.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "solmate/tokens/ERC20.sol";
import "forge-std/Test.sol";

contract LoanAgent is ILoanAgent {
  address public miner;
  address public owner;
  address public poolFactory;
  bool public active = false;

  constructor(address _miner, address _poolFactory) {
    miner = _miner;
    poolFactory = _poolFactory;
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

  function isDebtor() public view returns (bool) {
    for (uint256 i = 0; i < IPoolFactory(poolFactory).allPoolsLength(); ++i) {
      (uint256 bal,) = IPool4626(IPoolFactory(poolFactory).allPools(i)).loanBalance(address(this));
      if (bal > 0) {
        return true;
      }
    }
    return false;
  }

  function hasPenalties() public view returns (bool) {
    for (uint256 i = 0; i < IPoolFactory(poolFactory).allPoolsLength(); ++i) {
      (,uint256 penalty) = IPool4626(IPoolFactory(poolFactory).allPools(i)).loanBalance(address(this));
      if (penalty > 0) {
        return true;
      }
    }
    return false;
  }

  function revokeMinerOwnership(address newOwner) external {
    require(owner == msg.sender, "Only LoanAgent owner can call revokeOwnership");
    require(IMiner(miner).currentOwner() == address(this), "LoanAgent does not own miner");
    require(!isDebtor(), "Cannot revoke miner ownership with outstanding loans");

    active = false;
    IMiner(miner).changeOwnerAddress(newOwner);
  }

  function withdrawBalance() external returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  function getPool(uint256 poolID) internal view returns (IPool4626) {
    require(poolID <= IPoolFactory(poolFactory).allPoolsLength(), "Invalid pool ID");
    address pool = IPoolFactory(poolFactory).allPools(poolID);
    return IPool4626(pool);
  }

  function borrow(uint256 amount, uint256 poolID) external {
    require(owner == msg.sender, "Only LoanAgent owner can call borrow");
    require(!hasPenalties(), "Cannot borrow while loanAgent is in any pool's  penalty zone.");
    getPool(poolID).borrow(amount, address(this));
  }

  function repay(uint256 amount, uint256 poolID) external {
    require(owner == msg.sender, "Only LoanAgent owner can call repay");
    require(getPool(poolID).asset().balanceOf(address(this)) >= amount && amount >= 0, "Invalid amount passed to paydownDebt");
    if (amount == 0) amount = getPool(poolID).asset().balanceOf(address(this));
    IPool4626 pool = getPool(poolID);
    pool.asset().approve(address(pool), amount);
    pool.repay(amount, address(this), address(this));
  }
}

