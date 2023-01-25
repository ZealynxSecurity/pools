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
    address[] miners,
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

  // the current length of a payment window
  // NOTE: this is a constant value
  function windowLength() external view returns (uint256);
  // the current window deadline where an agent has to make a payment to each pool
  function nextPmtWindowDeadline() external view returns (uint256);
  // the full window info
  function windowInfo() external view returns (Window memory);

  // when an agent has minted more power than they have
  function isOverPowered(address agent) external view returns (bool);
  function isOverPowered(uint256 agentID) external view returns (bool);
  // when an agent owes more to the system than their aggregate expected rewards can cover
  function isOverLeveraged(address agent) external view returns (bool);
  function isOverLeveraged(uint256 agentID) external view returns (bool);
  // when an agent is both overPowered and overLeveraged
  function isInDefault(address agent) external view returns (bool);
  function isInDefault(uint256 agentID) external view returns (bool);

  function maxPoolsPerAgent() external view returns (uint256);

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  // checks if an agent is overPowered and changes state appropriately
  function checkPower(address agent, SignedCredential memory signedCredential) external returns (bool);
  // checks if an agent is overLeveraged and changes state appropriately
  function checkLeverage(address agent, SignedCredential memory signedCredential) external returns (bool);
    // checks if an agent is in default and makes the appropriate changes in the pools
  function checkDefault(address agent, SignedCredential memory signedCredential) external;

  // checks if a SignedCredential is valid, including checking the issuer against the ROLE_ISSUER
  function isValidCredential(address agent, SignedCredential memory signedCredential) external view returns (bool);

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  function addPoolToList(uint256 pool) external;

  function removePoolFromList(uint256 pool) external;

  // if an agent is overPowered, this function is callable by anyone
  // NOTE: this function is non-destructive,
  // it will burn only the available power tokens held by the agent at calltime
  function forceBurnPower(address agent, SignedCredential memory signedCredential) external;

  // if an agent is overLeveraged, this function is callable by the police admin
  // to decentralize later
  // NOTE: This function is non-destructive,
  // it will only draw available funds from the miner actor's but not take any executive, destructive actions
  // it will take all the available funds, and pay off pools pro rata to power token stakes
  function forceMakePayments(
    address agent,
    SignedCredential memory signedCredential
  ) external;

  // if an agent is overLeveraged, this function is callable by the police admin
  // to decentralize later
  function forcePullFundsFromMiners(
    address agent,
    address[] calldata miners,
    uint256[] calldata amounts
  ) external;

  // if an agent is in default, this function is callable by anyone
  // NOTE: This function IS DESTRUCTIVE
  // It prepares the miners to be completely liquidated as fast as possible
  // without interference from the miner's worker or control addresses
  // Off-chain liquidation must occur to complete the process
  function lockout(address agent) external;

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  // for expanding / contracting the payment window
  function setWindowLength(uint256 newWindowLength) external;
}
