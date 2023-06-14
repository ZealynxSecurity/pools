// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";

interface IAgentPolice {

  /*//////////////////////////////////////////////
                    EVENT LOGS
  //////////////////////////////////////////////*/

  event Defaulted(address agent);

  event OnAdministration(address agent);

  event FaultySectors(address indexed agentID, uint256 faultEpoch);

  /*//////////////////////////////////////////////
                      GETTERS
  //////////////////////////////////////////////*/

  function defaultWindow() external view returns (uint256);

  function maxPoolsPerAgent() external view returns (uint256);

  function agentApproved(VerifiableCredential calldata vc) external;

  function agentLiquidated(uint256 agentID) external view returns (bool);

  function paused() external view returns (bool);

  function maxDTE() external view returns (uint256);

  function maxLTV() external view returns (uint256);

  function maxConsecutiveFaultEpochs() external view returns (uint256);

  function maxEpochsOwedTolerance() external view returns (uint256);

  function sectorFaultyTolerancePercent() external view returns (uint256);

  /*//////////////////////////////////////////////
                    VC HANDLING
  //////////////////////////////////////////////*/

  function isValidCredential(
    uint256 agent,
    bytes4 action,
    SignedCredential calldata signedCredential
  ) external;

  function credentialUsed(uint8 v, bytes32 r, bytes32 s) external view returns (bool);

  function registerCredentialUseBlock(
    SignedCredential calldata signedCredential
  ) external;

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  function setAgentDefaulted(address agent) external;

  function putAgentOnAdministration(address agent, address administration) external;

  function markAsFaulty(IAgent[] calldata agents) external;

  function putAgentOnAdministrationDueToFaultySectorDays(address agent, address administration) external;

  function setAgentDefaultDueToFaultySectorDays(address agent) external;

  function setSectorFaultyTolerancePercent(uint256 percent) external;

  function setMaxConsecutiveFaultEpochs(uint256 epochs) external;

  function setMaxEpochsOwedTolerance(uint256 epochs) external;

  function setMaxDTE(uint256 dte) external;

  function setMaxLTV(uint256 ltv) external;

  function prepareMinerForLiquidation(address agent, uint64 miner, uint64 liquidator) external;

  function distributeLiquidatedFunds(address agent, uint256 amount) external;

  function confirmRmEquity(
    VerifiableCredential calldata vc
  ) external view;

  function confirmRmAdministration(
    VerifiableCredential calldata vc
  ) external view;

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setDefaultWindow(uint256 defaultWindow) external;

  function pause() external;

  function resume() external;
}
