// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {NewAgentData} from "test/helpers/NewCredentials.sol";
contract NewCredParser {
  uint256 constant NEW_DATA_LENGTH = 320;
  function getAgentValue(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).agentValue;
  }
  function getCollateralValue(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).collateralValue;
  }
  function getExpectedDailyRewards(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).expectedDailyRewards;
  }
  function getGCRED(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).gcred;
  }
  function getLockedFunds(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).lockedFunds;
  }
  function getPrincipal(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).principal;
  }
  function getQAPower(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).qaPower;
  }
  function getNewVariable(bytes memory _agentData) external pure returns (uint256) {
    return abi.decode(padBytes(_agentData), (NewAgentData)).newVariable;
  }

  function padBytes(bytes memory data) public pure returns (bytes memory) {
    bytes memory returnData = bytes.concat(data, new bytes(NEW_DATA_LENGTH - data.length));
    return returnData;
  }
}
