// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";

interface IAgent {

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  function version() external view returns (uint8);

  function id() external view returns (uint256);

  function newAgent() external view returns (address);

  function administration() external view returns (address);

  function defaulted() external view returns (bool);

  function borrowedPoolsCount() external view returns (uint256);

  function liquidAssets() external view returns (uint256);

  function adoRequestKey() external view returns (address);

  function faultySectorStartEpoch() external view returns (uint256);

  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function addMiner(
    SignedCredential memory sc
  ) external;

  function removeMiner(
    address newMinerOwner,
    SignedCredential memory sc
  ) external;

  function migrateMiner(uint64 miner) external;

  function changeMinerWorker(
    uint64 miner,
    uint64 worker,
    uint64[] calldata controlAddresses
  ) external;

  function decommissionAgent(address newAgent) external;

  function setInDefault() external;

  function setAdministration(address administration) external;

  function prepareMinerForLiquidation(uint64 miner, address liquidator) external;

  function setFaulty() external;

  function setRecovered(SignedCredential memory sc) external;

  function setAdoRequestKey(address adoRequestKey) external;

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  function withdraw(
    address receiver,
    SignedCredential memory signedCred
  ) external;

  function borrow(
    uint256 poolID,
    SignedCredential memory signedCred
  ) external;

  function pay(
    uint256 poolID,
    SignedCredential memory signedCred
  ) external returns (
    uint256 rate,
    uint256 epochsPaid,
    uint256 principalPaid,
    uint256 refund
  );

  function pullFunds(
    SignedCredential memory signedCred
  ) external;

  function pushFunds(
    SignedCredential memory signedCred
  ) external;
}
