// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";

contract EchidnaAgent is EchidnaSetup {
    constructor() payable {}

    function test_agent_borrow() public {
        // borrowAmount = bound(borrowAmount, WAD, MAX_FIL);
        uint256 borrowAmount = WAD;

        IAgent agent = _configureAgent(AGENT_OWNER);
        uint256 agentID = agent.id();

        // ensure theres enough to deposit
        hevm.deal(INVESTOR, borrowAmount + WAD);
        hevm.prank(INVESTOR);
        pool.deposit{value: borrowAmount}(INVESTOR);

        // 2x liquidation value will always pass
        uint256 liquidationValue = borrowAmount * 2;
        // fund the agent with its liquidation value to pass the check
        hevm.deal(address(agent), liquidationValue);
        SignedCredential memory sc = _issueBorrowCred(agentID, borrowAmount, liquidationValue);

        uint256 agentLiquidAssetsBefore = agent.liquidAssets();

        // @audit this fails, not sure why
        hevm.prank(AGENT_OWNER);
        agent.borrow(poolID, sc);

        // never reaches
        assert(false);
    }

    function test_credential_actions() public {
        uint256 agentID = 1;
        uint64 minerID = 1;

        SignedCredential memory sc = _issueAddMinerCred(agentID, minerID);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.addMiner.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 principal = 10e18;
        uint256 liquidationValue = 5e18;
        sc = _issueBorrowCred(agentID, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.borrow.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 paymentAmount = 1e18;
        sc = _issuePayCred(agentID, principal, liquidationValue, paymentAmount);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.pay.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        sc = _issueRemoveMinerCred(agentID, minerID, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.removeMiner.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }

        uint256 amount = 5e18;
        sc = _issueWithdrawCred(agentID, amount, principal, liquidationValue);
        try GetRoute.agentPolice(router).isValidCredential(agentID, IAgent.withdraw.selector, sc) {
            assert(true);
        } catch {
            assert(false);
        }
    }
}
