interface ICredentials {
  function getAssets(bytes memory _agentData) external pure returns (uint256);
  function getQAPower(bytes memory _agentData) external pure returns (uint256);
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256);
  function getLiabilities(bytes memory _agentData) external pure returns (uint256);
}