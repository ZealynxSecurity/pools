interface ICredentials {
  function getAgentValue(bytes memory _agentData) external pure returns (uint256);
  function getBaseRate(bytes memory _agentData) external pure returns (uint256);
  function getQAPower(bytes memory _agentData) external pure returns (uint256);
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256);
  function getPrincipal(bytes memory _agentData) external pure returns (uint256);
  function getGCRED(bytes memory _agentData) external pure returns (uint256);
}
