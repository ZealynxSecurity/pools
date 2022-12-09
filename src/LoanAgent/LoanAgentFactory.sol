// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/LoanAgent/LoanAgent.sol";
import "src/Router/RouterAware.sol";

interface ILoanAgentFactory {
  function create(address _miner) external returns (address);
  function revokeOwnership(address _loanAgent) external;
  function loanAgents(address loanAgent) external view returns (bool);
  function activeMiners(address miner) external view returns (address);
}

contract LoanAgentFactory is RouterAware {
  mapping(address => bool) public loanAgents;
  string public verifierName;
  string public verifiedVersion;


  constructor(string memory _name, string memory _version) {
    verifierName = _name;
    verifiedVersion = _version;
  }

  function create() external returns (address) {
    LoanAgent loanAgent = new LoanAgent(router, verifierName, verifiedVersion);
    loanAgents[address(loanAgent)] = true;
    // What's the reasoning behind returning this address? Are we consuming it anywhere?
    return address(loanAgent);
  }

  function setVerifierName(string memory _name, string memory _version) external {
    // TODO: Add Role based permissions
    verifierName = _name;
    verifiedVersion = _version;
  }


}
