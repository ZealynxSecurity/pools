// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Script.sol";
import "src/MockMiner.sol";
import "src/LoanAgent/ILoanAgent.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/LoanAgent/MinerRegistry.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/Pool/SimpleInterestPool.sol";
import "src/Stats/Stats.sol";
import "src/VCVerifier/VCVerifier.sol";

// used for deploying GCRED to anvil for local testing and development
contract DemoDeploy is Script {
    WFIL public wFIL;
    // This order matters when instantiating the router
    MinerRegistry public registry;
    LoanAgentFactory public loanAgentFactory;
    PoolFactory public poolFactory;
    VCVerifier public vcVerifier;
    Stats public stats;

    Router public router;

    // Should this name-space be changed to just glif.io?
    string constant public VERIFIED_NAME = "glif.io";
    string constant public VERIFIED_VERSION = "1";

    function configureLoanAgent() public returns (LoanAgent, MockMiner) {
        MockMiner miner = new MockMiner();
        // give miner some fake rewards and vest them over 1000 epochs
        vm.deal(address(miner), 100e18);
        miner.lockBalance(block.number, 1000, 100e18);
        // create a loan agent for miner
        // Why are you wrapping this as payable?
        LoanAgent loanAgent = LoanAgent(
        payable(
            loanAgentFactory.create()
        ));
        // propose the change owner to the loan agent
        miner.changeOwnerAddress(address(loanAgent));
        // confirm change owner address (loanAgent1 now owns miner)
        loanAgent.addMiner(address(miner));

        require(miner.currentOwner() == address(loanAgent));
        require(loanAgent.owner() == msg.sender);
        require(loanAgent.hasMiner(address(miner)));

        vm.stopPrank();
        return (loanAgent, miner);
    }

    function run() public {
        vm.startBroadcast();
        address treasury = vm.envAddress("TREASURY_ADDR");

        wFIL = new WFIL();
        registry = new MinerRegistry();
        loanAgentFactory = new LoanAgentFactory(VERIFIED_NAME, VERIFIED_VERSION);
        poolFactory = new PoolFactory(wFIL, treasury);
        vcVerifier = new VCVerifier(VERIFIED_NAME, VERIFIED_VERSION);
        stats = new Stats();

        router = new Router(
            address(loanAgentFactory),
            address(poolFactory),
            address(vcVerifier),
            address(stats),
            address(registry)
        );

        loanAgentFactory.setRouter(address(router));
        poolFactory.setRouter(address(router));
        vcVerifier.setRouter(address(router));
        stats.setRouter(address(router));

        configureLoanAgent();
        configureLoanAgent();

        poolFactory.createSimpleInterestPool("POOL1", 20e18);
        poolFactory.createSimpleInterestPool("POOL2", 15e18);

        vm.stopBroadcast();
    }
}
