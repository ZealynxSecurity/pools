// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {PoolToken} from "./Tokens/PoolToken.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolAccounting} from "src/Pool/PoolAccounting.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_TREASURY} from "src/Constants/Routes.sol";

contract PoolFactory is IPoolFactory, RouterAware {
  ERC20 public asset;
  address[] public allPools;
  mapping(address => bool) public templates;
  mapping(address => bool) public brokers;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth() virtual {
    AuthController.requiresSubAuth(router, address(this));
    _;
  }

  constructor(ERC20 _asset) {
    asset = _asset;
  }

  function createSymbol() internal view returns (string memory) {
    bytes memory b;
    b = abi.encodePacked("P");
    b = abi.encodePacked(b, Strings.toString(allPools.length));
    b = abi.encodePacked(b, "GLIF");

    return string(b);
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  function createPool(
      string calldata name,
      string calldata symbol,
      address operator,
      address broker,
      address template
    ) external requiresAuth returns (IPool pool) {
    require(brokers[broker], "Pool: Broker not approved");
    require(templates[template], "Pool: Template not approved");
    // Create custom ERC20 for the pools
    // TODO: What should the token symbol and name be?
    PoolToken token = new PoolToken(name, symbol);
    pool = new PoolAccounting(router, broker, address(asset), address(token), template);
    token.transferOwnership(address(pool.template()));
    allPools.push(address(pool));

    AuthController.initPoolRoles(router, address(pool), operator, address(this));
  }

  function isPool(address pool) external view returns (bool) {
    for (uint256 i = 0; i < allPools.length; i++) {
      if (allPools[i] == pool) {
        return true;
      }
    }
    return false;
  }

  function isPoolTemplate(address pool) external view returns (bool) {
    return templates[pool];
  }

  function approveBroker(address broker) external requiresAuth {
    brokers[broker] = true;
  }

  function approveTemplate(address template) external requiresAuth {
    templates[template] = true;
  }

  // TODO: Not sure about side effects of removing live versions? Should be safe - deprecation
  function revokeBroker(address broker) external requiresAuth {
    brokers[broker] = false;
  }

  function revokeTemplate(address template) external requiresAuth {
    templates[template] = false;
  }
}
