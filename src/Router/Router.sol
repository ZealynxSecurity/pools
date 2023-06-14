// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Ownable} from "src/Auth/Ownable.sol";

contract Router is IRouter, Ownable {

  address constant ADDRESS_ZERO = address(0);
  error RouteDNE();

  mapping(bytes4 => address) public route;
  mapping(bytes32 => Account) private _accounts;

  constructor(address owner) Ownable(owner) {}

  function getRoute(bytes4 id) public view returns (address) {
    address _route = route[id];
    if (_route == ADDRESS_ZERO) revert RouteDNE();
    return _route;
  }

  function getRoute(string calldata id) external view returns (address) {
    return getRoute(bytes4(keccak256(bytes(id))));
  }

  function pushRoute(bytes4 id, address newRoute) public onlyOwner {
    route[id] = newRoute;

    emit PushRoute(newRoute, id);
  }

  function pushRoute(string calldata id, address newRoute) public onlyOwner {
    pushRoute(bytes4(keccak256(bytes(id))), newRoute);
  }

  function pushRoutes(string[] calldata ids, address[] calldata newRoutes) external onlyOwner {
    if (ids.length != newRoutes.length) revert InvalidParams();
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }

  function pushRoutes(bytes4[] calldata ids, address[] calldata newRoutes) external onlyOwner {
    if (ids.length != newRoutes.length) revert InvalidParams();
    for (uint i = 0; i < ids.length; i++) {
      pushRoute(ids[i], newRoutes[i]);
    }
  }

  function getAccount(
    uint256 agentID,
    uint256 poolID
  ) external view returns (Account memory) {
    return _accounts[createAccountKey(agentID, poolID)];
  }

  function setAccount(
    uint256 agentID,
    uint256 poolID,
    Account calldata account
  ) external {
    if (address(GetRoute.pool(GetRoute.poolRegistry(address(this)), poolID)) != msg.sender) {
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
