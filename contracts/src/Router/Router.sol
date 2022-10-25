// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Router is Ownable {
  /**
    0 - loanAgentFactory
    1 - poolFactory
    2 - vcVerifier
    3 - stats
    4 - ? TBD
   */
  address[] public routes;

  constructor(
    address _loanAgentFactory,
    address _poolFactory,
    address _vcVerifier,
    address _stats
  ) {
    routes = [_loanAgentFactory, _poolFactory, _vcVerifier, _stats];
  }

  function getRoute(uint8 id) public view returns (address) {
    return routes[id];
  }

  function getLoanAgentFactory() public view returns (address) {
    return getRoute(0);
  }

  function getPoolFactory() public view returns (address) {
    return getRoute(1);
  }

  function getVCVerifier() public view returns (address) {
    return getRoute(2);
  }

  function getStats() public view returns (address) {
    return getRoute(3);
  }

  function pushRoute(address newRoute) public onlyOwner returns (uint8) {
    uint8 routeID = uint8(routes.length);
    routes.push(newRoute);
    return routeID;
  }
}
