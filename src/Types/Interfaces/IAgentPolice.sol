// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {AgentBeneficiary} from "src/Types/Structs/Beneficiary.sol";

interface IAgentPolice {

  /*//////////////////////////////////////////////
                    EVENT LOGS
  //////////////////////////////////////////////*/

  event Defaulted(address agent);

  event OnAdministration(address agent);

  event OffAdministration(address agent);

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

  /*//////////////////////////////////////////////
                    VC HANDLING
  //////////////////////////////////////////////*/

  function isValidCredential(
    uint256 agent,
    bytes4 action,
    SignedCredential memory signedCredential
  ) external;

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

  function rmAgentFromAdministration(address agent) external;

  function prepareMinerForLiquidation(address agent, uint64 miner) external;

  function distributeLiquidatedFunds(uint256 agentID, uint256 amount) external;

  function liquidatedAgent(address agentID) external;

  function confirmRmEquity(
    VerifiableCredential memory vc,
    uint256 additionalLiability
  ) external view;

  /*//////////////////////////////////////////////
                    BENEFICIARIES
  //////////////////////////////////////////////*/

  function isBeneficiaryActive(uint256 agentID) external view returns (bool);

  function agentBeneficiary(uint256 agentID) external view returns (AgentBeneficiary memory);

  function changeAgentBeneficiary(
    address newBeneficiary,
    uint256 agentID,
    uint256 expiration,
    uint256 quota
  ) external;

  function approveAgentBeneficiary(uint256 agentID) external;

  function beneficiaryWithdrawable(
    address recipient,
    address sender,
    uint256 agentID,
    uint256 proposedAmount
  ) external returns (
    uint256 amount
  );

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setDefaultWindow(uint256 defaultWindow) external;

  function pause() external;

  function resume() external;
}
