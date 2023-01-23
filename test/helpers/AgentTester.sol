// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import "src/Types/Structs/Filecoin.sol";

contract AgentSigTester {
  // AGENT_ADD_MINERS_SELECTOR
  function addMiners(address[] calldata) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_REMOVE_MINER_SELECTOR
  function removeMiner(
    address,
    address,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_CHANGE_MINER_WORKER_SELECTOR
  function changeMinerWorker(
    address,
    ChangeWorkerAddressParams calldata
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_CHANGE_MINER_MULTIADDRS_SELECTOR
  function changeMultiaddrs(
    address,
    ChangeMultiaddrsParams calldata
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_CHANGE_MINER_PEER_ID_SELECTOR
  function changePeerID(
    address,
    ChangePeerIDParams calldata
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // SET_OPERATOR_ROLE_SELECTOR
  function setOperatorRole(address, bool) external pure returns (bytes4) {
    return msg.sig;
  }

  // SET_OWNER_ROLE_SELECTOR
  function setOwnerRole(address, bool) external pure returns (bytes4) {
    return msg.sig;
  }

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/

  // AGENT_MINT_POWER_SELECTOR
  function mintPower(
    uint256,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_BURN_POWER_SELECTOR
  function burnPower(
    uint256,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  // AGENT_WITHDRAW_BALANCE_SELECTOR
  function withdrawBalance(address,uint256) external pure returns (bytes4) {
    return msg.sig;
  }

  function withdrawBalance(address,uint256,SignedCredential memory) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_PULL_FUNDS_SELECTOR
  function pullFundsFromMiners(
    address[] calldata,
    uint256[] calldata
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_PUSH_FUNDS_SELECTOR
  function pushFundsToMiners(
    address[] calldata,
    uint256[] calldata
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_BORROW_SELECTOR
  function borrow(
    uint256,
    uint256,
    SignedCredential memory,
    uint256
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_EXIT_SELECTOR
  function exit(
    uint256,
    uint256,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_MAKE_PAYMENTS_SELECTOR
  function makePayments(
    uint256[] calldata,
    uint256[] calldata,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // AGENT_STAKE_TO_MAKE_PAYMENTS_SELECTOR
  function stakeToMakePayments(
    uint256[] calldata,
    uint256[] calldata,
    uint256[] calldata,
    SignedCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }
}
