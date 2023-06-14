// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";

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
