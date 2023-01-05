// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";

contract PoolImplementation is IPoolImplementation {
  uint256 rate;
  constructor (uint256 _rate) {
    rate = _rate;
  }

  function getRate(
    uint256 borrowAsk,
    uint256 powerTokenStake,
    uint256 windowLength,
    Account memory account,
    VerifiableCredential memory vc
  ) external pure returns (uint256) {
    return 0;
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
      uint256 powerTokenStake,
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
