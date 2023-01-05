// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import "src/Types/Structs/Filecoin.sol";

contract PoolFactorySigTester {
  function approveImplementation(address) external pure returns (bytes4) {
    return msg.sig;
  }

  function revokeImplementation(address) external pure returns (bytes4) {
    return msg.sig;
  }

  function approveTemplate(address) external pure returns (bytes4) {
    return msg.sig;
  }

  function revokeTemplate(address) external pure returns (bytes4) {
    return msg.sig;
  }

  function setTreasuryFeeRate(uint256) external pure returns (bytes4) {
    return msg.sig;
  }

  function createPool(
      string memory,
      string memory,
      address,
      address
    ) external pure returns (bytes4) {
    return msg.sig;
  }

  function setFeeThreshold(uint256) external pure returns (bytes4) {
    return msg.sig;
  }
}
