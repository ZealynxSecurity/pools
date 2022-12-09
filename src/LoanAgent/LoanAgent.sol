// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import "src/LoanAgent/ILoanAgent.sol";
import "src/LoanAgent/IMinerRegistry.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/VCVerifier/VCVerifier.sol";
import "solmate/tokens/ERC20.sol";
import {Router} from "src/Router/Router.sol";
import {IStats} from "src/Stats/IStats.sol";

contract LoanAgent is ILoanAgent, VCVerifier {
  address[] public override miners;
  mapping(address => bool) public hasMiner;

  constructor(address _router, string memory _name, string memory _version)
    VCVerifier(_name, _version) {
    setRouter(_router);
    renounceOwnership();
  }


  function addMiner(address miner) external {
    _addMiner(miner);
  }

  function removeMiner(address miner) external {
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        _removeMiner(i);
        break;
      }
    }
  }

  function removeMiner(uint256 index) external {
    _removeMiner(index);
  }

  function minerCount() external view returns (uint256) {
    return miners.length;
  }


  // this function does two things:
  // 1. it sets the miner's owner addr to be the loan agent
  // 2. it sets the loan agent's owner to be the old miner owner
  // only the miner's current owner can claim ownership over that miner's loan agent
  function _claimOwnership(address miner) internal {
    // TODO: needs a solution for FVM <> EVM compatibility
    // TODO: Confirm that the sender has correct perms to claim this miner
    IMiner(miner).changeOwnerAddress(address(this));
    // if this call does not error out, set the owner of this loan agent to be the sender of this message
  }

  // TODO: add role based auth to this function
  function revokeOwnership(address newOwner, address miner) public {
    require(IMiner(miner).currentOwner() == address(this), "LoanAgent does not own miner");
    require(!IStats(Router(router).getStats()).isDebtor(address(this)), "Cannot revoke miner ownership with outstanding loans");
    IMiner(miner).changeOwnerAddress(newOwner);
    // What's the intention here?
    ILoanAgentFactory(Router(router).getLoanAgentFactory()).revokeOwnership(address(this));
  }

  function withdrawBalance(address miner) external returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  // TODO: add role based auth to this function
  function borrow(uint256 amount, uint256 poolID) external {
    _getPool(poolID).borrow(amount, address(this));
  }

  // TODO: add role based auth to this function
  function repay(uint256 amount, uint256 poolID) external  {
    require(_getPool(poolID).asset().balanceOf(address(this)) >= amount && amount >= 0, "Invalid amount passed to paydownDebt");
    if (amount == 0) amount = _getPool(poolID).asset().balanceOf(address(this));
    IPool4626 pool = _getPool(poolID);
    pool.asset().approve(address(pool), amount);
    pool.repay(amount, address(this), address(this));
  }

  function owner() public view override(Ownable, ILoanAgent) returns (address) {
    return Ownable.owner();
  }

  // Internal functions


  function _getPool(uint256 poolID) internal view returns (IPool4626) {
    IPoolFactory poolFactory = IPoolFactory(Router(router).getPoolFactory());
    require(poolID <= poolFactory.allPoolsLength(), "Invalid pool ID");
    address pool = poolFactory.allPools(poolID);
    return IPool4626(pool);
  }
  
  function _addMiner(address miner) internal {
    require(hasMiner[miner] == false, "Miner already added");
    IMinerRegistry(Router(router).getMinerRegistry()).addMiner(miner);
    hasMiner[miner] = true;
    _claimOwnership(miner);
    miners.push(miner);
  }

  function _removeMiner(uint256 index) internal {
    // Confirm the miner is valid and can be removed
    require(index < miners.length, "Invalid index");
    require(_canRemoveMiner(index), "Cannot remove miner unless all loans are paid off or it isn't needed for collateral");

    // Remove the miner from the central registry
    IMinerRegistry(Router(router).getMinerRegistry()).removeMiner(miners[index]);

    // Update state to reflect the miner removal
    hasMiner[miners[index]] = false;
    revokeOwnership(msg.sender, miners[index]);
    miners[index] = miners[miners.length - 1];
    miners.pop();
  }

  function _canRemoveMiner(uint256 index) internal view returns (bool) {
    return !IStats(Router(router).getStats()).isDebtor(address(this)) || _evaluateCollateral(index);
  }

  function _evaluateCollateral(uint256 index) internal view returns (bool) {
    return true;
  }

  fallback() external payable {  }

}

