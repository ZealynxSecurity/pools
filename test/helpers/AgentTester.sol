// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// import {SignedCredential} from "src/Types/Structs/Credentials.sol";
// import "src/Types/Structs/Filecoin.sol";

// contract AgentSigTester {
//   // AGENT_ADD_MINERS_SELECTOR
//   function addMiners(uint64[] calldata) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_REMOVE_MINER_SELECTOR
//   function removeMiner(
//     address,
//     uint64,
//     SignedCredential memory,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_CHANGE_MINER_WORKER_SELECTOR
//   function changeMinerWorker(
//     uint64,
//     uint64,
//     uint64[] memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // SET_OPERATOR_ROLE_SELECTOR
//   function setOperatorRole(address, bool) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // SET_OWNER_ROLE_SELECTOR
//   function setOwnerRole(address, bool) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   /*//////////////////////////////////////////////////
//                 POWER TOKEN FUNCTIONS
//   //////////////////////////////////////////////////*/

//   // AGENT_MINT_POWER_SELECTOR
//   function mintPower(
//     uint256,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_BURN_POWER_SELECTOR
//   function burnPower(
//     uint256,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   /*//////////////////////////////////////////////
//                 FINANCIAL FUNCTIONS
//   //////////////////////////////////////////////*/
//   function withdraw(address,uint256,SignedCredential memory) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_PULL_FUNDS_SELECTOR
//   function pullFundsFromMiners(
//     uint64[] calldata,
//     uint256[] calldata,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_PUSH_FUNDS_SELECTOR
//   function pushFundsToMiners(
//     uint64[] calldata,
//     uint256[] calldata,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_BORROW_SELECTOR
//   function borrow(
//     uint256,
//     uint256,
//     SignedCredential memory,
//     uint256
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_EXIT_SELECTOR
//   function exit(
//     uint256,
//     uint256,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // AGENT_MAKE_PAYMENTS_SELECTOR
//   function makePayments(
//     uint256[] calldata,
//     uint256[] calldata,
//     SignedCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }


// }
