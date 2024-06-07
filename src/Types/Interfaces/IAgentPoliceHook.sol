// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
 
interface IAgentPoliceHook {
  function onCredentialUsed(address agent, VerifiableCredential calldata vc) external;
}
