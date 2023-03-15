// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import "src/Types/Structs/Filecoin.sol";

interface IAgent {

  /*//////////////////////////////////////////////////
                        EVENTS
  //////////////////////////////////////////////////*/

  event MigrateMiner(address indexed oldAgent, address indexed newAgent, uint64 indexed miner);

  event ChangeMinerWorker(uint64 indexed miner, uint64 newWorker, uint64[] newControlAddresses);

  event WithdrawBalance(address indexed receiver, uint256 amount);

  event PullFundsFromMiners(uint64[] miners, uint256[] amounts);

  event PushFundsToMiners(uint64[] miners, uint256[] amounts);

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  function id() external view returns (uint256);

  function miners(uint256) external view returns (uint64);

  function minersCount() external view returns (uint256);

  function hasMiner(uint64 miner) external view returns (bool);

  // powerTokensMinted - powerTokensBurned
  function totalPowerTokensStaked() external view returns (uint256);

  function powerTokensStaked(uint256 poolID) external view returns (uint256 powerTokensStaked);

  function stakedPoolsCount() external view returns (uint256);

  function maxWithdraw(SignedCredential memory sc) external view returns (uint256);

  function liquidAssets() external view returns (uint256);


  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function addMiners(uint64[] calldata miners) external;

  function removeMiner(
    address newMinerOwner,
    uint64 miner,
    SignedCredential memory agentCred,
    SignedCredential memory minerCred
  ) external;

  function migrateMiner(address newAgent, uint64 miner) external;

  function changeMinerWorker(
    uint64 miner,
    uint64 worker,
    uint64[] calldata controlAddresses
  ) external;

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
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory signedCredential
  ) external;

  function pushFundsToMiners(
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory signedCredential
  ) external;
}
