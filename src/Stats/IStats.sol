// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this v1 loan agent is configured to pay off all loans before allowing the owner of the loan agent to take any rewards home
interface IStats {
  function isDebtor(address loanAgent) external view returns (bool);
  function isDebtor(address loanAgent, uint256 poolID) external view returns (bool);

  function hasPenalties(address loanAgent) external returns (bool);
  function hasPenalties(address loanAgent, uint256 poolID) external returns (bool);

  function isLoanAgent(address loanAgent) external returns (bool);
}
