// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/LoanAgent/MinerRegistry.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/Router/Router.sol";
import "src/Stats/Stats.sol";
import "src/VCVerifier/VCVerifier.sol";

/**
  This BaseTest contract sets up an environment equipped with:
  - LoanAgentFactory
  - PoolFactory
  - WFIL
  - Stats
  - Credit scorer
  - Router
 */
contract BaseTest is Test {
  address public treasury = makeAddr('TREASURY');

  WFIL public wFIL;
  // This order matters when instantiating the router
  MinerRegistry registry;
  LoanAgentFactory public loanAgentFactory;
  PoolFactory public poolFactory;
  VCVerifier public vcVerifier;
  Stats public stats;

  Router public router;

  // Should this name-space be changed to just glif.io?
  string constant public VERIFIED_NAME = "glif.io";
  string constant public VERIFIED_VERSION = "1";

  constructor() {
    wFIL = new WFIL();
    registry = new MinerRegistry();
    loanAgentFactory = new LoanAgentFactory(VERIFIED_NAME, VERIFIED_VERSION);
    poolFactory = new PoolFactory(wFIL, treasury);
    vcVerifier = new VCVerifier("glif.io", "1");
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
  }

  function configureLoanAgent(address minerOwner) public returns (LoanAgent, MockMiner) {
    vm.startPrank(minerOwner);
    MockMiner miner = new MockMiner();
    // give miner some fake rewards and vest them over 1000 epochs
    vm.deal(address(miner), 100e18);
    miner.lockBalance(block.number, 1000, 100e18);
    // create a loan agent for miner
    LoanAgent loanAgent = LoanAgent(
      payable(
        loanAgentFactory.create()
      ));
    // propose the change owner to the loan agent
    miner.changeOwnerAddress(address(loanAgent));
    // confirm change owner address (loanAgent1 now owns miner)
    loanAgent.addMiner(address(miner));

    require(miner.currentOwner() == address(loanAgent), "Miner owner not set");
    require(loanAgent.hasMiner(address(miner)), "Miner not registered");

    vm.stopPrank();
    return (loanAgent, miner);
  }
}
