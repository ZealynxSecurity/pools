// SPDX-License-Identifier: UNLICENSED
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

  function poolIDs(uint256 agentID) external view returns (uint256[] memory);

  function defaultWindow() external view returns (uint256);

  function maxPoolsPerAgent() external view returns (uint256);

  function agentApproved(VerifiableCredential memory vc) external;

  function liquidated(uint256 agentID) external view returns (bool);

  function paused() external view returns (bool);

  function maxDTE() external view returns (uint256);

  function maxConsecutiveFaultEpochs() external view returns (uint256);

  function sectorFaultyTolerancePercent() external view returns (uint256);

  /*//////////////////////////////////////////////
                    VC HANDLING
  //////////////////////////////////////////////*/

  function isValidCredential(
    uint256 agent,
    bytes4 action,
    SignedCredential memory signedCredential
  ) external;

  function credentialUsed(uint8 v, bytes32 r, bytes32 s) external view returns (bool);

  function registerCredentialUseBlock(
    SignedCredential memory signedCredential
  ) external;

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  function addPoolToList(uint256 agentID, uint256 pool) external;

  function removePoolFromList(uint256 agentID, uint256 pool) external;

  function setAgentDefaulted(address agent) external;

  function putAgentOnAdministration(address agent, address administration) external;

  function markAsFaulty(IAgent[] calldata agents) external;

  function putAgentOnAdministrationDueToFaultySectorDays(address agent, address administration) external;

  function setAgentDefaultDueToFaultySectorDays(address agent) external;

  function setSectorFaultyTolerancePercent(uint256 percent) external;

  function setMaxConsecutiveFaultEpochs(uint256 epochs) external;

  function prepareMinerForLiquidation(address agent, uint64 miner) external;

  function distributeLiquidatedFunds(address agent, uint256 amount) external;

  function liquidatedAgent(address agent) external;

  function confirmRmEquity(
    VerifiableCredential memory vc
  ) external view;

  function confirmRmAdministration(
    VerifiableCredential memory vc
  ) external view;

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setDefaultWindow(uint256 defaultWindow) external;

  function pause() external;

  function resume() external;
}
