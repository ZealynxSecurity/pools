// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_TREASURY} from "src/Constants/Routes.sol";

contract PoolFactory is IPoolFactory, RouterAware {
  ERC20 public asset;
  address[] public allPools;

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
      string memory _name,
      string memory _symbol,
      address operator,
      address rateModule
    ) external returns (IPool pool) {
    pool = new PoolTemplate(_name, _symbol, router, rateModule, address(asset));
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
}
