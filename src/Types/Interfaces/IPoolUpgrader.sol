// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

interface IPoolUpgrader {
    function upgrade(address agentPolice, address pool) external payable;
    function refreshProtocolRoutes(address[] calldata agents) external;
    function verifyTotalAssets(uint256 newInterestAccrued) external returns (bool);
}
