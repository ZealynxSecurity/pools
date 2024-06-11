// SPDX-License-Identifier: UNLICENSED
// solhint-disable
pragma solidity 0.8.17;

import {VerifiableCredential, SignedCredential} from "v0/Types/Structs/Credentials.sol";

interface IVCVerifier {
  function digest(
    VerifiableCredential calldata vc
  ) external view returns(bytes32);

  // validates a signed credential
  function validateCred(
    uint256 agent,
    bytes4 selector,
    SignedCredential calldata
  ) external;

  function recover(
    SignedCredential calldata
  ) external view returns (address);
}
