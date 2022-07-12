// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this v1 loan agent is configured to pay off all loans before allowing the owner of the loan agent to take any rewards home
interface Rewards {
  // gets rewards from a loan agent
  // returns how much FIL was distributed to the transmuter and how much is reinvested in the tranche by buying tTokens off the open market (auto compound)
  function distribute(uint256 amount) external returns (uint256, uint256);
}
