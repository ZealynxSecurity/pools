// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";

interface IAgentPolice {

  /*//////////////////////////////////////////////
                    EVENT LOGS
  //////////////////////////////////////////////*/

  // emitted when `checkPower` gets called
  event CheckPower(
    address indexed agent,
    address indexed checker,
    bool overPowered
  );
  // emitted when `checkLeverage` moves an agent into the overLeveraged state
  event CheckLeverage(
    address indexed agent,
    address indexed checker,
    bool overLeveraged
  );

  event CheckDefault(
    address indexed agent,
    address indexed checker,
    bool inDefault
  );
  // emitted when `checkPower` and `checkLeverage` become simultaneously true
  event InDefault(address indexed agent);
  // emitted when the agent is brought out of default
  event OutOfDefault(address indexed agent);

  // emitted when `forceBurnPower` is called on an agent
  // stillOverPowered is `true` when the burning still does not bring down the minted power below the actual power amount
  event ForceBurnPower(
    address indexed agent,
    address indexed burner,
    uint256 amountBurned,
    bool stillOverPowered
  );
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

  function windowLength() external view returns (uint256);

  function defaultWindow() external view returns (uint256);

  function nextPmtWindowDeadline() external view returns (uint256);

  function windowInfo() external view returns (Window memory);

  function isOverPowered(address agent) external view returns (bool);

  function isOverPowered(uint256 agentID) external view returns (bool);

  function isOverLeveraged(address agent) external view returns (bool);

  function isOverLeveraged(uint256 agentID) external view returns (bool);

  function isInDefault(address agent) external view returns (bool);

  function isInDefault(uint256 agentID) external view returns (bool);

  function maxPoolsPerAgent() external view returns (uint256);

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  function checkPower(address agent, SignedCredential memory signedCredential) external returns (bool);

  function checkLeverage(address agent, SignedCredential memory signedCredential) external returns (bool);

  function checkDefault(address agent, SignedCredential memory signedCredential) external;

  function isValidCredential(address agent, SignedCredential memory signedCredential) external;

  function registerCredentialUseBlock(SignedCredential memory signedCredential) external;

  function isAgentOverLeveraged(uint256 agentID, VerifiableCredential memory vc) external;

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  function addPoolToList(uint256 pool) external;

  function removePoolFromList(uint256 pool) external;

  function forceBurnPower(address agent, SignedCredential memory signedCredential) external;

  function forceMakePayments(
    address agent,
    SignedCredential memory signedCredential
  ) external;

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

  function setWindowLength(uint256 newWindowLength) external;
}
