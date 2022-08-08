// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/LoanAgent/LoanAgent.sol";
import "src/LoanAgent/LoanAgentFactory.sol";
import "src/MockMiner.sol";

contract BaseTest is Test {
  function setUpMiner(address _owner, address _loanAgentFactory) public returns (MockMiner, LoanAgent) {
      // create 2 miners and assign them each a loan agent
      vm.startPrank(_owner);
      MockMiner miner = new MockMiner();
      // give miner some fake rewards
      vm.deal(address(miner), 100 ether);
      miner.lockBalance(block.number, 100, 100 ether);
      // create a loan agent for miner
      LoanAgent loanAgent = LoanAgent(
        payable(
          ILoanAgentFactory(_loanAgentFactory).create(address(miner))
        ));
      // propose the change owner to the loan agent
      miner.changeOwnerAddress(address(loanAgent));
      // confirm change owner address (loanAgent1 now owns miner)
      loanAgent.claimOwnership();

      require(miner.currentOwner() == address(loanAgent));
      require(loanAgent.owner() == _owner);
      require(loanAgent.miner() == address(miner));

      vm.stopPrank();
      return (miner, loanAgent);
  }
}
