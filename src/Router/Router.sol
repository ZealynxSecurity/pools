// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import {Routes} from "src/Router/Routes.sol";
import {IRouter} from "src/Router/IRouter.sol";

contract Router is IRouter {
  mapping(bytes4 => address) public route;

  constructor(
    address _agentFactory,
    address _poolFactory,
    address _vcVerifier,
    address _stats,
    address _minerRegistry,
    address _authority,
    address _powerToken
  ) {
    route[Routes.AGENT_FACTORY] = _agentFactory;
    route[Routes.POOL_FACTORY] = _poolFactory;
    route[Routes.VC_VERIFIER] = _vcVerifier;
    route[Routes.STATS] = _stats;
    route[Routes.MINER_REGISTRY] = _minerRegistry;
    route[Routes.AUTHORITY] = _authority;
    route[Routes.POWER_TOKEN] = _powerToken;
  }

  function getRoute(bytes4 id) public view returns (address) {
    return route[id];
  }

  function getRoute(string memory id) public view returns (address) {
    return getRoute(bytes4(keccak256(bytes(id))));
  }


  function pushRoute(bytes4 id, address newRoute) public returns (bytes4) {
    route[id] = newRoute;

    emit PushRoute(newRoute, id);

    return id;
  }

  function pushRoute(string memory id, address newRoute) public returns (bytes4) {
    return pushRoute(bytes4(keccak256(bytes(id))), newRoute);
  }
}
