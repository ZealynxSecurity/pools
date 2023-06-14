// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.15;

import {UpgradedAgent} from "test/helpers/UpgradedAgent.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";

/// @dev this is to reduce contract size in AgentFactory
contract UpgradedAgentDeployer {
  uint8 public constant version = 2;

  function deploy(
    address router,
    uint256 agentId,
    address owner,
    address operator,
    address adoRequestKey
  ) external returns (IAgent agent) {
    agent = new UpgradedAgent(agentId, router, owner, operator, adoRequestKey);
  }
}
