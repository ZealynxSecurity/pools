// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";

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

  function isAgentOverLeveraged(VerifiableCredential memory vc) external;

  function liquidated(uint256 agentID) external view returns (bool);

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

  function prepareMinerForLiquidation(address agent, address liquidator, uint64 miner) external;

  function distributeLiquidatedFunds(uint256 agentID, uint256 amount) external;

  function liquidatedAgent(address agentID) external;

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setDefaultWindow(uint256 defaultWindow) external;
}
