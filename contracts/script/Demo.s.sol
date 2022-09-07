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
import "../src/Pool/SimpleInterestPool.sol";

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
        address treasury = vm.envAddress("TREASURY_ADDR");
        WFIL wFil = new WFIL();

        // deploy 2 simple interest pools
        PoolFactory poolFactory = new PoolFactory(wFil, treasury);
        // 20% simple interest pool
        IPool4626 pool1 = poolFactory.createSimpleInterestPool("POOL1", 20e18);
        // 15% simple interest pool
        IPool4626 pool2 = poolFactory.createSimpleInterestPool("POOL2", 15e18);

        // // temp https://github.com/glif-confidential/gcred/issues/26
        // wFil.deposit{value: 100e18}();
        // wFil.approve(address(pool1), 100e18);
        // wFil.approve(address(pool2), 100e18);

        // deploy 2 miners with their loan agent's configured
        loanAgentFactory = new LoanAgentFactory(address(poolFactory));
        setUpMiner();
        setUpMiner();
        vm.stopBroadcast();
    }
}
