// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this v1 loan agent is configured to pay off all loans before allowing the owner of the loan agent to take any rewards home
interface ILoanAgent {
  // withdraws any available balance from the miner by calling withdrawBalance
  // will return 0 if any unpaid loans are still active
  function withdrawBalance() external returns (uint256);
  // takeLoan steps:
  // 1. exchanges tTokens owned by loan agent for FIL via the Swap actor
  // 2. sends received FIL to the miner actor
  // 3. pledges received FIL as the miner actor (calls applyReward on the miner)
  function takeLoan(uint256 amount, uint256 poolID) external returns (uint256);
  // calls withdrawBalance on the miner to take earned FIL and pay down loan amount
  function paydownDebt(uint256 poolID) external returns (uint256);
}
