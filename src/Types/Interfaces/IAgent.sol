// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import "src/Types/Structs/Filecoin.sol";

interface IAgent {

  /*//////////////////////////////////////////////////
                        EVENTS
  //////////////////////////////////////////////////*/

  event MigrateMiner(address indexed oldAgent, address indexed newAgent, address indexed miner);

  event ChangeMultiaddrs(address indexed miner, bytes[] newMultiaddrs);

  event ChangeMinerWorker(address indexed miner, bytes newWorker, bytes[] newControlAddresses);

  event ChangePeerID(address indexed miner, bytes newPeerID);

  event SetOperatorRole(address indexed operator, bool enabled);

  event SetOwnerRole(address indexed owner, bool enabled);

  event WithdrawBalance(address indexed receiver, uint256 amount);

  event PullFundsFromMiners(address[] miners, uint256[] amounts);

  event PushFundsToMiners(address[] miners, uint256[] amounts);

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  function id() external view returns (uint256);

  function hasMiner(address miner) external view returns (bool);

  // powerTokensMinted - powerTokensBurned
  function totalPowerTokensStaked() external view returns (uint256);

  function powerTokensStaked(uint256 poolID) external view returns (uint256 powerTokensStaked);

  function stakedPoolsCount() external view returns (uint256);

  function maxWithdraw(SignedCredential memory sc) external view returns (uint256);

  function liquidAssets() external view returns (uint256);


  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function addMiners(address[] calldata miners) external;

  function removeMiner(
    address newMinerOwner,
    address miner,
    SignedCredential memory agentCred,
    SignedCredential memory minerCred
  ) external;

  function migrateMiner(address newAgent, address miner) external;

  function changeMinerWorker(
    address miner,
    ChangeWorkerAddressParams calldata params
  ) external;

  function changeMultiaddrs(
    address miner,
    ChangeMultiaddrsParams calldata params
  ) external;

  function changePeerID(
    address miner,
    ChangePeerIDParams calldata params
  ) external;

  /*//////////////////////////////////////////////////
          AGENT OWNERSHIP / OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function setOperatorRole(address operator, bool enabled) external;

  function setOwnerRole(address owner, bool enabled) external;

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/

  function mintPower(
    uint256 amount,
    SignedCredential memory sc
  ) external;

  function burnPower(
    uint256 amount,
    SignedCredential memory sc
  ) external returns (uint256 burnedAmt);

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  function withdrawBalance(address receiver, uint256 amount) external;

  function withdrawBalance(
    address receiver,
    uint256 amount,
    SignedCredential memory signedCredential
  ) external;

  function borrow(
    uint256 amount,
    uint256 poolID,
    SignedCredential memory vc,
    uint256 powerTokenAmount
  ) external;

  function exit(
    uint256 poolID,
    uint256 assetAmount,
    SignedCredential memory vc
  ) external;

  function makePayments(
    uint256[] calldata poolIDs,
    uint256[] calldata amounts,
    SignedCredential memory vc
  ) external;

  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
    uint256 additionalPowerTokens,
    SignedCredential memory signedCredential
  ) external;

  function pullFundsFromMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external;

  function pushFundsToMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external;
}
