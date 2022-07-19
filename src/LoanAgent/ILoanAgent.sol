// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this v1 loan agent is configured to pay off all loans before allowing the owner of the loan agent to take any rewards home
interface LoanAgent {
  // withdraws any available balance from the miner by calling withdrawBalance
  // will return 0 if any unpaid loans are still active
  function withdrawBalance() external returns (uint256);
  // v0 mintCredit assumptions:
  // mints the maximium amount of credit possible
  // mints only 1 type of credit (single tranche system)
  // returns the amount of credit minted
  // mintCredit mints new tTokens and gives the loan agent contract ownership over them
  function mintCredit() external returns (uint256);
  // takeLoan steps:
  // 1. exchanges tTokens owned by loan agent for FIL via the Swap actor
  // 2. sends received FIL to the miner actor
  // 3. pledges received FIL as the miner actor (calls applyReward on the miner)
  function takeLoan() external returns (uint256);
  // calls withdrawBalance on the miner to take earned FIL and pay down loan amount
  function paydownDebtFromRewards() external returns (uint256);
}
