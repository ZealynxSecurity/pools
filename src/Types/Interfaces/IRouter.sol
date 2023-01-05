// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Account} from "src/Types/Structs/Account.sol";

/**
 * @dev Router interface provides functions for getting routes
 * to other contracts
 */
interface IRouter {
    event PushRoute(address newRoute, bytes4 id);

    function getRoute(bytes4 id) external view returns (address);
    function getRoute(string memory id) external view returns (address);
    function pushRoute(bytes4 id, address newRoute) external;
    function pushRoute(string memory id, address newRoute) external;
    function pushRoutes(bytes4[] calldata id, address[] calldata newRoute) external;
    function pushRoutes(string[] calldata id, address[] calldata newRoute) external;
    function getAccount(uint256 agentID, uint256 poolID) external view returns (Account memory);
    function setAccount(uint256 agentID, uint256 poolID, Account memory account) external;
}

interface IRouterAware {
    function router() external view returns (address);

    function setRouter(address router) external;
}
