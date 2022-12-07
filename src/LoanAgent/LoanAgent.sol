// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import "src/LoanAgent/ILoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/VCVerifier/VCVerifier.sol";
import "solmate/tokens/ERC20.sol";
import {Router} from "src/Router/Router.sol";
import {IStats} from "src/Stats/IStats.sol";

contract LoanAgent is ILoanAgent, VCVerifier {
  address public miner;

  constructor(address _miner, address _router, string memory _name, string memory _version)
    VCVerifier(_name, _version) {
    miner = _miner;
    setRouter(_router);
    renounceOwnership();
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
    _transferOwnership(_msgSender());
  }

  function revokeOwnership(address newOwner) external onlyOwner {
    require(IMiner(miner).currentOwner() == address(this), "LoanAgent does not own miner");
    require(!IStats(Router(router).getStats()).isDebtor(address(this)), "Cannot revoke miner ownership with outstanding loans");
    IMiner(miner).changeOwnerAddress(newOwner);
    ILoanAgentFactory(Router(router).getLoanAgentFactory()).revokeOwnership(address(this));
  }

  function withdrawBalance() external returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  function getPool(uint256 poolID) internal view returns (IPool4626) {
    IPoolFactory poolFactory = IPoolFactory(Router(router).getPoolFactory());
    require(poolID <= poolFactory.allPoolsLength(), "Invalid pool ID");
    address pool = poolFactory.allPools(poolID);
    return IPool4626(pool);
  }

  function borrow(uint256 amount, uint256 poolID) external onlyOwner {
    getPool(poolID).borrow(amount, address(this));
  }

  function repay(uint256 amount, uint256 poolID) external onlyOwner {
    require(getPool(poolID).asset().balanceOf(address(this)) >= amount && amount >= 0, "Invalid amount passed to paydownDebt");
    if (amount == 0) amount = getPool(poolID).asset().balanceOf(address(this));
    IPool4626 pool = getPool(poolID);
    pool.asset().approve(address(pool), amount);
    pool.repay(amount, address(this), address(this));
  }

  function owner() public view override(Ownable, ILoanAgent) returns (address) {
    return Ownable.owner();
  }

}

