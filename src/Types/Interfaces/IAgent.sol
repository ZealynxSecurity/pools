// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

interface IAgent {
  function miners(uint256 index) external returns (address);
  function withdrawBalance(address miner) external returns (uint256);
  function borrow(uint256 amount, uint256 poolID, VerifiableCredential memory vc, uint256 powerTokenAmount, uint8 v, bytes32 r, bytes32 s) external;
  function exit(uint256 poolID, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external;
  function revokeOwnership(address newOwner, address miner) external;
  // for dealing with power tokens
  function mintPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external;
  function burnPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external;
}
