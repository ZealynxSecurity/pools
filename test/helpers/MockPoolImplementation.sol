// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

contract MockPoolImplementation is IPoolImplementation, RouterAware {
  using FixedPointMathLib for uint256;

  uint256 rate;

  constructor (uint256 _rate, address _router) {
    rate = _rate;
    router = _router;
  }

  function getRate(
    uint256 borrowAsk,
    uint256 powerTokenStake,
    uint256 windowLength,
    Account memory account,
    VerifiableCredential memory vc
  ) external view returns (uint256) {
    // hardcode 20% rate (per annum)
    uint256 apy = 0.2e18;
    return apy.divWadUp(EPOCHS_IN_YEAR*1e18);
  }

  function getPenalty(
    uint256 penaltyEpochs,
    uint256 windowLength,
    Account memory account,
    VerifiableCredential memory vc
  ) external pure returns (uint256) {
    return 0;
  }

  function beforeBorrow(
    uint256 borrowAsk,
    uint256 powerTokenStake,
    Account memory account,
    VerifiableCredential memory vc
  ) external pure {}

  function beforeExit(
      uint256 exitAmount,
      Account memory account,
      VerifiableCredential memory vc
  ) external pure {}

  function beforeMakePayment(
      uint256 paymentAmount,
      Account memory account
  ) external pure {}

  function beforeStakeToPay(
      uint256 paymentAmount,
      uint256 powerTokenAmount,
      Account memory account
  ) external pure {}
}
