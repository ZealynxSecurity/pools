// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./EchidnaSetup.sol";

import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {MockMiner} from "test/helpers/MockMiner.sol";
import {Agent} from "src/Agent/Agent.sol";

contract EchidnaAgent is EchidnaSetup {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address internal constant INVESTOR_1 = address(0x70000);
    address internal constant MINER_OWNER_1 = address(0x80000);

    uint64 miner;
    IAgent agent;

    constructor() payable {
        miner = _newMiner(MINER_OWNER_1);
        // agent = _configureAgent(MINER_OWNER_1, miner);
    }

    // AgentTestHelper
    function _newMiner(address minerOwner) internal returns (uint64 id) {
        hevm.prank(minerOwner);
        MockMiner mockMiner = new MockMiner(minerOwner);

        id = MockIDAddrStore(MinerHelper.ID_STORE_ADDR).addAddr(address(mockMiner));
        mockMiner.setID(id);
    }

    // function _configureAgent(address minerOwner, uint64 _miner) internal returns (IAgent _agent) {
    //     IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
    //     hevm.prank(minerOwner);
    //     _agent = Agent(payable(agentFactory.create(minerOwner, minerOwner, makeAddr("ADO_REQUEST_KEY"))));
    //     assert(_miner.isOwner(minerOwner));
    //     hevm.stopPrank();

    //     _agentClaimOwnership(address(agent), _miner, minerOwner);
    //     return IAgent(address(_agent));
    // }
}