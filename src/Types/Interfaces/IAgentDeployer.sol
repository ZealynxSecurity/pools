// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Interface for the Agent Deployer contract
import {IAgent} from "src/Types/Interfaces/IAgent.sol";

interface IAgentDeployer {
    function deploy(
      address router,
      uint256 agentId,
      address owner,
      address operator
    ) external returns (IAgent agent);
}
