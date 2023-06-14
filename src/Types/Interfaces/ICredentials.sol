// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

interface ICredentials {
  function getAgentValue(bytes memory _agentData) external pure returns (uint256);
  function getCollateralValue(bytes memory _agentData) external pure returns (uint256);
  function getQAPower(bytes memory _agentData) external pure returns (uint256);
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256);
  function getPrincipal(bytes memory _agentData) external pure returns (uint256);
  function getGCRED(bytes memory _agentData) external pure returns (uint256);
  function getLockedFunds(bytes memory _agentData) external pure returns (uint256);
  function getFaultySectors(bytes memory _agentData) external pure returns (uint256);
  function getLiveSectors(bytes memory _agentData) external pure returns (uint256);
  function getGreenScore(bytes memory _agentData) external pure returns (uint256);
}
