// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";

interface ILoanAgentFactory {
  function create(address _miner) external returns (address);
}

contract LoanAgentFactory {
  address public poolFactory;
  mapping(address => address) public loanAgents;
  mapping(address => address) public activeMiners;

  constructor(address _poolFactory) {
    poolFactory = _poolFactory;
  }

  function create(address _miner) public returns (address) {
    // can only have 1 loan agent per miner
    if (activeMiners[_miner] != address(0)) {
      return activeMiners[_miner];
    }

    LoanAgent loanAgent = new LoanAgent(_miner, poolFactory);
    loanAgents[address(loanAgent)] = _miner;
    activeMiners[_miner] = address(loanAgent);
    return address(loanAgent);
  }
}
