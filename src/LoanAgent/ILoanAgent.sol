import {VerifiableCredential} from "src/VCVerifier/VCVerifier.sol";

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this v1 loan agent is configured to pay off all loans before allowing the owner of the loan agent to take any rewards home
interface ILoanAgent {
  function miners(uint256 index) external returns (address);
  function withdrawBalance(address miner) external returns (uint256);
  function borrow(uint256 amount, uint256 poolID) external;
  function repay(uint256 amount, uint256 poolID) external;
  function revokeOwnership(address newOwner, address miner) external;
  // for dealing with power tokens
  function mintPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external;
  function burnPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external;
}
