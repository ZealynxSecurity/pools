// SPDX-License-Identifier: UNLICENSED
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
  function getLockedFunds(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).lockedFunds;
  }
  function getPrincipal(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).principal;
  }
  function getQAPower(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(_agentData, (AgentData)).qaPower;
  }
}
