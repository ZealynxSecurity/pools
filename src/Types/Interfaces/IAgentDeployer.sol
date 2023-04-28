// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

// Interface for the Agent Deployer contract
interface IAgentDeployer {
    function deploy(
      address router,
      uint256 agentId,
      address owner,
      address operator,
      bytes calldata publicKey
    ) external returns (address agent);
}
