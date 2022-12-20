// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Router/Routes.sol";
import {IRouter} from "src/Router/IRouter.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {Auth} from "src/Auth/Auth.sol";

contract Router is IRouter {
  mapping(bytes4 => address) public route;

  constructor(
    address coreAuthority
  ) {
    route[ROUTE_CORE_AUTHORITY] = coreAuthority;
  }

/**
 * @dev Modifier to check if the caller is authorized to call a function on this contract
 *
 * @notice For deployment reasons, we also check to see if the caller is the core authority's owner
 * This allows us to pushRoutes to the router during deployment before setting up the router's roles
 */
  modifier requiresAuth() virtual {
    require(
      RoleAuthority.canCall(address(this), address(this)),
      "Router: Not authorized"
    );
    _;
  }

  function getRoute(bytes4 id) public view returns (address) {
    return route[id];
  }

  function getRoute(string memory id) public view returns (address) {
    return getRoute(bytes4(keccak256(bytes(id))));
  }


  function pushRoute(bytes4 id, address newRoute) public requiresAuth {
    route[id] = newRoute;

    emit PushRoute(newRoute, id);
  }

  function pushRoute(string memory id, address newRoute) public requiresAuth {
    pushRoute(bytes4(keccak256(bytes(id))), newRoute);
  }

  function pushRoutes(string[] calldata ids, address[] calldata newRoutes) public requiresAuth {
    require(ids.length == newRoutes.length, "Router: ids and newRoutes must be same length");
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }

  function pushRoutes(bytes4[] calldata ids, address[] calldata newRoutes) public requiresAuth {
    require(ids.length == newRoutes.length, "Router: ids and newRoutes must be same length");
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }
}
