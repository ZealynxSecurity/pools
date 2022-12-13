// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import "src/Auth/Auth.sol";
import "src/LoanAgent/ILoanAgent.sol";
import "src/LoanAgent/IMinerRegistry.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/VCVerifier/VCVerifier.sol";
import "solmate/tokens/ERC20.sol";
import "src/PowerToken/IPowerToken.sol";
import {Router} from "src/Router/Router.sol";
import {IStats} from "src/Stats/IStats.sol";

contract LoanAgent is ILoanAgent, VCVerifier {
  address[] public override miners;
  mapping(address => bool) public hasMiner;
  uint256 powerTokensMinted = 0;
  bool redZone = false;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth() virtual {
    require(Authority(Router(router).getAuthority()).canCall(msg.sender, address(this), msg.sig), "LoanAgent: Not authorized");
    _;
  }

  constructor(address _router, string memory _name, string memory _version)
    VCVerifier(_name, _version) {
    setRouter(_router);
  }

  /*//////////////////////////////////////////////////
                MINER OWNERSHIP CHANGES
  //////////////////////////////////////////////////*/

  function addMiner(address miner) external requiresAuth {
    _addMiner(miner);
  }

  function removeMiner(address miner) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        _removeMiner(i);
        break;
      }
    }
  }

  function removeMiner(uint256 index) external requiresAuth {
    _removeMiner(index);
  }

  function minerCount() external view returns (uint256) {
    return miners.length;
  }

  function revokeOwnership(address newOwner, address miner) public requiresAuth{
    require(IMiner(miner).currentOwner() == address(this), "LoanAgent does not own miner");
    require(!IStats(Router(router).getStats()).isDebtor(address(this)), "Cannot revoke miner ownership with outstanding loans");
    IMiner(miner).changeOwnerAddress(newOwner);
    ILoanAgentFactory(Router(router).getLoanAgentFactory()).revokeOwnership(address(this));
  }

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/

  function mintPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external {
    require(!redZone, "LoanAgent: Cannot mint power while Agent is in the red zone");
    require(isValid(vc, v, r, s), "Invalid VC");
    require(vc.miner.qaPower > powerTokensMinted + amount, "Cannot mint more power than the miner has");

    IPowerToken(Router(router).getPowerToken()).mint(amount);
    powerTokensMinted += amount;
  }

  function burnPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external {
    require(isValid(vc, v, r, s), "Invalid VC");
    IPowerToken powerToken = IPowerToken(Router(router).getPowerToken());
    require(amount <= powerToken.balanceOf(address(this)), "LoanAgent: Cannot burn more power than the agent holds");

    powerToken.burn(amount);
    powerTokensMinted -= amount;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/
  function withdrawBalance(address miner) external requiresAuth returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  function borrow(uint256 amount, uint256 poolID) external {
    _getPool(poolID).borrow(amount, address(this));
  }

  function repay(uint256 amount, uint256 poolID) external {
    require(_getPool(poolID).asset().balanceOf(address(this)) >= amount && amount >= 0, "Invalid amount passed to paydownDebt");
    if (amount == 0) amount = _getPool(poolID).asset().balanceOf(address(this));
    IPool4626 pool = _getPool(poolID);
    pool.asset().approve(address(pool), amount);
    pool.repay(amount, address(this), address(this));
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

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

  function _claimOwnership(address miner) internal {
    IMiner(miner).changeOwnerAddress(address(this));
  }

  function _canRemoveMiner(uint256 index) internal view returns (bool) {
    return !IStats(Router(router).getStats()).isDebtor(address(this)) || _evaluateCollateral(index);
  }

  function _evaluateCollateral(uint256 index) internal view returns (bool) {
    return true;
  }

  fallback() external payable {  }
}

