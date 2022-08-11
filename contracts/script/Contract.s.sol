// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";

// used for deploying GCRED to anvil for local testing and development
contract DemoDeploy is Script {
    function setUp() public {}

    function run() public {
        vm.broadcast();
    }
}
