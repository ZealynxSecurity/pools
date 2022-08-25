// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "../src/MockMiner.sol";
import "../src/LoanAgent/ILoanAgent.sol";
import "../src/LoanAgent/LoanAgentFactory.sol";
import "../src/LoanAgent/LoanAgent.sol";
import "../src/LoanAgent/LoanAgentFactory.sol";
import "../src/MockMiner.sol";
import "../src/WFIL.sol";
import "../src/Pool/PoolFactory.sol";
import "../src/Pool/IPool4626.sol";

// used for deploying GCRED to anvil for local testing and development
contract DemoDeploy is Script {
    LoanAgentFactory loanAgentFactory;
    function setUpMiner() public {
        MockMiner miner = new MockMiner();
        // give miner some fake rewards
        vm.deal(address(miner), 10*1e18);
        miner.lockBalance(block.number, 100, 10*1e18);
        // create a loan agent for miner
        LoanAgent loanAgent = LoanAgent(
            payable(loanAgentFactory.create(address(miner)))
        );
        // propose the change owner to the loan agent
        miner.changeOwnerAddress(address(loanAgent));
        // confirm change owner address (loanAgent1 now owns miner)
        loanAgent.claimOwnership();
    }

    function run() public {
        vm.startBroadcast();
        address treasury = address(msg.sender);
        WFIL wFil = new WFIL();
        PoolFactory poolFactory = new PoolFactory(wFil, treasury);
        loanAgentFactory = new LoanAgentFactory(address(poolFactory));
        setUpMiner();
        setUpMiner();
        vm.stopBroadcast();
    }
}
