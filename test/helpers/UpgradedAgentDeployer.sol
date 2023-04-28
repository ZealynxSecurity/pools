// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {UpgradedAgent} from "test/helpers/UpgradedAgent.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";

/// @dev this is to reduce contract size in AgentFactory
contract UpgradedAgentDeployer {
  function deploy(
    address router,
    uint256 agentId,
    address owner,
    address operator,
    bytes calldata publicKey
  ) external returns (IAgent agent) {
    agent = new UpgradedAgent(router, agentId, owner, operator, publicKey);
  }
}
