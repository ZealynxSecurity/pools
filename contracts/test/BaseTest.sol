// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";
import "src/WFIL.sol";
import "src/Pool/PoolFactory.sol";
import "src/Pool/IPool4626.sol";
import "src/Router/Router.sol";
import "src/Stats/Stats.sol";
import "src/CreditScore/CreditScore.sol";

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
  LoanAgentFactory public loanAgentFactory;
  PoolFactory public poolFactory;
  CreditScore public creditScore;
  Stats public stats;

  Router public router;

  constructor() {
    wFIL = new WFIL();
    loanAgentFactory = new LoanAgentFactory();
    poolFactory = new PoolFactory(wFIL, treasury);
    creditScore = new CreditScore();
    stats = new Stats();

    router = new Router(
      address(loanAgentFactory),
      address(poolFactory),
      address(creditScore),
      address(stats)
    );

    loanAgentFactory.setRouter(address(router));
    poolFactory.setRouter(address(router));
    creditScore.setRouter(address(router));
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
        loanAgentFactory.create(address(miner))
      ));
    // propose the change owner to the loan agent
    miner.changeOwnerAddress(address(loanAgent));
    // confirm change owner address (loanAgent1 now owns miner)
    loanAgent.claimOwnership();

    require(miner.currentOwner() == address(loanAgent));
    require(loanAgent.owner() == minerOwner);
    require(loanAgent.miner() == address(miner));

    vm.stopPrank();
    return (loanAgent, miner);
  }
}
