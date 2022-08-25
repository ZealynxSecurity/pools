// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "../src/MockMiner.sol";

// used for deploying GCRED to anvil for local testing and development
contract DemoDeploy is Script {
    function deployMiners() public {

    }

    function run() public {
        vm.broadcast();
        string memory mnemonic = vm.envString("MNEMONIC");
        console.log(mnemonic);
        uint256 deployerPk = vm.deriveKey(mnemonic, 0);
        address deployerAddr = vm.addr(deployerPk);



        console.log("deployerAddr", deployerAddr);
        MockMiner miner = new MockMiner();
        vm.stopBroadcast();
    }
}
