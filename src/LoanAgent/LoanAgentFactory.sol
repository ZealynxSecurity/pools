// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";

contract LoanAgentFactory {
  mapping(address => address) public loanAgents;
  mapping(address => address) public activeMiners;

  function create(address _miner) public returns (address) {
    // can only have 1 loan agent per miner
    if (activeMiners[_miner] != address(0)) {
      return activeMiners[_miner];
    }

    LoanAgent loanAgent = new LoanAgent(_miner);
    loanAgents[address(loanAgent)] = _miner;
    activeMiners[_miner] = address(loanAgent);
    return address(loanAgent);
  }
}
