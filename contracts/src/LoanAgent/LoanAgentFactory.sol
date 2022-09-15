// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";
import "src/Router/RouterAware.sol";

interface ILoanAgentFactory {
  function create(address _miner) external returns (address);
  function loanAgents(address loanAgent) external returns (address);
  function activeMiners(address miner) external returns (address);
}

contract LoanAgentFactory is RouterAware {
  mapping(address => address) public loanAgents;
  mapping(address => address) public activeMiners;
  uint256 public count = 0;

  function create(address _miner) public returns (address) {
    // can only have 1 loan agent per miner
    if (activeMiners[_miner] != address(0)) {
      return activeMiners[_miner];
    }

    LoanAgent loanAgent = new LoanAgent(_miner, router);
    loanAgents[address(loanAgent)] = _miner;
    activeMiners[_miner] = address(loanAgent);
    count += 1;
    return address(loanAgent);
  }
}
