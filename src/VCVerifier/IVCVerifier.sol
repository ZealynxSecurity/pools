// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/VCVerifier/VCVerifier.sol";

interface IVCVerifier {
  function digest(
    VerifiableCredential memory vc
  ) external view returns(bytes32);

  function isValid(
    VerifiableCredential memory vc,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external view returns (bool);

  function recover(
    VerifiableCredential memory vc,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external view returns (bool);
}
