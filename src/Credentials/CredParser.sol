// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {AgentData} from "src/Types/Structs/Credentials.sol";

contract CredParser {
  function getAgentValue(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).agentValue;
  }
  function getCollateralValue(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).collateralValue;
  }
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).expectedDailyRewards;
  }
  function getGCRED(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).gcred;
  }
  function getPrincipal(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).principal;
  }
  function getQAPower(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).qaPower;
  }
  function getFaultySectors(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).faultySectors;
  }
  function getLiveSectors(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).liveSectors;
  }
  function getGreenScore(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).greenScore;
  }
}
