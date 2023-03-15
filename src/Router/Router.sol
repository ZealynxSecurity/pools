// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Unauthorized} from "src/Errors.sol";
import {Ownable} from "src/Auth/Ownable.sol";

contract Router is IRouter, Ownable {
  mapping(bytes4 => address) public route;
  mapping(bytes32 => Account) private _accounts;

  constructor(address owner) Ownable(owner) {}

  function getRoute(bytes4 id) public view returns (address) {
    return route[id];
  }

  function getRoute(string memory id) public view returns (address) {
    return getRoute(bytes4(keccak256(bytes(id))));
  }

  function pushRoute(bytes4 id, address newRoute) public onlyOwner {
    route[id] = newRoute;

    emit PushRoute(newRoute, id);
  }

  function pushRoute(string memory id, address newRoute) public onlyOwner {
    pushRoute(bytes4(keccak256(bytes(id))), newRoute);
  }

  function pushRoutes(string[] calldata ids, address[] calldata newRoutes) public onlyOwner {
    require(ids.length == newRoutes.length, "Router: ids and newRoutes must be same length");
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }

  function pushRoutes(bytes4[] calldata ids, address[] calldata newRoutes) public onlyOwner {
    require(ids.length == newRoutes.length, "Router: ids and newRoutes must be same length");
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }

  function getAccount(
    uint256 agentID,
    uint256 poolID
  ) public view returns (Account memory) {
    return _accounts[createAccountKey(agentID, poolID)];
  }

  function setAccount(
    uint256 agentID,
    uint256 poolID,
    Account memory account
  ) public {
    if (!GetRoute.poolFactory(address(this)).isPoolTemplate(msg.sender)) {
      revert Unauthorized();
    }
    _accounts[createAccountKey(agentID, poolID)] = account;
  }

  function createAccountKey(
    uint256 agentID,
    uint256 poolID
  ) public pure returns (bytes32) {
    return bytes32(keccak256(abi.encodePacked(agentID, poolID)));
  }
}
