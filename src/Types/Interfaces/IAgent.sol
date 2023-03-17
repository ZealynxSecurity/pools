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

  function borrowedPoolsCount() external view returns (uint256);

  function liquidAssets() external view returns (uint256);

  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function addMiners(
    SignedCredential memory sc
  ) external;

  function removeMiner(
    address newMinerOwner,
    SignedCredential memory sc
  ) external;

  function migrateMiner(address newAgent, uint64 miner) external;

  function changeMinerWorker(
    uint64 miner,
    uint64 worker,
    uint64[] calldata controlAddresses
  ) external;

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  function withdrawBalance(
    address receiver,
    SignedCredential memory sc
  ) external;

  function borrowV2(
    uint256 poolID,
    SignedCredential memory sc
  ) external;

  function pay(
    uint256 amount,
    uint256 poolID,
    SignedCredential memory signedCred
  ) external returns (uint256 epochsPaid);

  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
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
