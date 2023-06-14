// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// Interface for the Agent Deployer contract
interface IAgentDeployer {
    function version() external view returns (uint8);

    function deploy(
      address router,
      uint256 agentId,
      address owner,
      address operator,
      address adoRequestKey
    ) external returns (address agent);
}
