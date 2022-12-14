// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Agent/Agent.sol";
import "src/Router/RouterAware.sol";

contract AgentFactory is RouterAware {
  mapping(address => bool) public agents;
  string public verifierName;
  string public verifiedVersion;

  constructor(string memory _name, string memory _version) {
    verifierName = _name;
    verifiedVersion = _version;
  }

  function create() external returns (address) {
    Agent agent = new Agent(router, verifierName, verifiedVersion);
    agents[address(agent)] = true;
    // What's the reasoning behind returning this address? Are we consuming it anywhere?
    return address(agent);
  }

  function setVerifierName(string memory _name, string memory _version) external {
    // TODO: Add Role based permissions
    verifierName = _name;
    verifiedVersion = _version;
  }


}
