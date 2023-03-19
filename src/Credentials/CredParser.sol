// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;
import {AgentData} from "src/Types/Structs/Credentials.sol";

contract CredParser {
  function getAgentValue(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).agentValue;
  }
  function getQAPower(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).qaPower;
  }
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).expectedDailyRewards;
  }
  function getPrincipal(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).principal;
  }
}
