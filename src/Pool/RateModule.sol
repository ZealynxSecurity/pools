// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

contract RateModule {
  uint256 rate;
  constructor (uint256 _rate) {
    rate = _rate;
  }

  function getRate(VerifiableCredential memory vc, uint256 amount) external view returns (uint256) {
    // Add checks for loan acceptance here
    return rate;
  }
}
