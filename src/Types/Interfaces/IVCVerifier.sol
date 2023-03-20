// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";

interface IVCVerifier {
  function digest(
    VerifiableCredential memory vc
  ) external view returns(bytes32);

  // validates a signed credential
  function validateCred(
    uint256 agent,
    bytes4 selector,
    SignedCredential memory
  ) external;

  function recover(
    SignedCredential memory
  ) external view returns (address);
}
