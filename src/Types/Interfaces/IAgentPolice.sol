// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";

interface IAgentPolice {

  /*//////////////////////////////////////////////
                    EVENT LOGS
  //////////////////////////////////////////////*/

  // emitted when `forceMakePayments` is called successfully
  // stillOverLeveraged is `true` when the payments still do not bring down the total owed under the expected rewards
  event ForceMakePayments(
    address indexed agent,
    address indexed caller,
    uint256[] poolIDs,
    uint256[] pmts,
    bool stillOverLeveraged
  );

  event ForcePullFundsFromMiners(
    address agent,
    uint64[] miners,
    uint256[] amounts
  );

  event Lockout(
    address indexed agent,
    address indexed locker
  );

  /*//////////////////////////////////////////////
                      GETTERS
  //////////////////////////////////////////////*/

  function poolIDs(uint256 agentID) external view returns (uint256[] memory);

  function defaultWindow() external view returns (uint256);

  function isInDefault(uint256 agentID) external view returns (bool);

  function maxPoolsPerAgent() external view returns (uint256);

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  function isValidCredential(uint256 agent, bytes4 action, SignedCredential memory signedCredential) external;

  function registerCredentialUseBlock(SignedCredential memory signedCredential) external;

  function isAgentOverLeveraged(VerifiableCredential memory vc) external;

  function checkDefault(SignedCredential memory signedCredential) external returns (bool);

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  function addPoolToList(uint256 pool) external;

  function removePoolFromList(uint256 agentID, uint256 pool) external;

  function forcePullFundsFromMiners(
    address agent,
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory signedCredential
  ) external;

  function lockout(address agent, uint64 miner) external;

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setDefaultWindow(uint256 defaultWindow) external;
}
