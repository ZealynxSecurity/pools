// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Router {
  /**
    0 - loanAgentFactory
    1 - poolFactory
    2 - vcVerifier
    3 - stats
    4 - minerRegistry
    5 - authority
    6 - powerToken
   */
  address[] public routes;

  constructor(
    address _loanAgentFactory,
    address _poolFactory,
    address _vcVerifier,
    address _stats,
    address _minerRegistry,
    address _authority,
    address _powerToken
  ) {
    routes = [_loanAgentFactory, _poolFactory, _vcVerifier, _stats, _minerRegistry, _authority, _powerToken];
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

  function getMinerRegistry() public view returns (address) {
    return getRoute(4);
  }

  function getAuthority() public view returns (address) {
    return getRoute(5);
  }

  function getPowerToken() public view returns (address) {
    return getRoute(6);
  }

  function pushRoute(address newRoute) public returns (uint8) {
    uint8 routeID = uint8(routes.length);
    routes.push(newRoute);
    return routeID;
  }
}
