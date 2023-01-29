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

  /**
   * @dev gets the rate for a given borrow ask, power token stake, window length, account and verifiable credential
   * @param borrowAsk - The amount the Agent is asking for
   * @param powerTokenStake - The amount of power tokens the Agent is willing to pledge for the ask
   * @param windowLength - The window length
   * @param account - The Agent's current Account with this specific Pool
   * @param vc - The (pre authorized) credential from the issuer
   * @return rate - The rate for the given borrow ask
   *
   * @notice this call will revert if the borrow ask is denied
   */
  function getRate(
    uint256 borrowAsk,
    uint256 powerTokenStake,
    uint256 windowLength,
    Account memory account,
    VerifiableCredential memory vc
  ) external pure returns (uint256) {
    return 0;
  }

  /**
   * @dev Computes the rate spike per epoch penalty
   * @param penaltyEpochs The number of epochs the account has been in penalty for
   * @param windowLength The length of the rate window
   * @param account The borrower's account
   * @return rateSpike - The rate spike penalty
   * @notice the `rateSpike` is an additiona per epoch rate applied on top of
   * the account's regular perEpochRate
   */
  function rateSpike(
    uint256 penaltyEpochs,
    uint256 windowLength,
    Account memory account
  ) external pure returns (uint256) {
    return 0;
  }

  /**
   * @dev Returns the minimum collateral required for a given account and verifiable credential
   * @param account The account for which the `minCollateral` is being calculated
   * @param vc The (pre-authorized) agent credential used to calculate the `minCollateral` amount
   * @return minCollateral - The minimum amount of liquid assets the Agent must have in order to borrow
   */
  function minCollateral(
    Account memory account,
    VerifiableCredential memory vc
  ) external pure returns (uint256) {
    return 0;
  }

  /**
   * @dev A hook that gets called before borrowing
   * @param borrowAsk The amount the Agent is asking for
   * @param powerTokenStake The amount of power tokens the Agent is willing to pledge for the ask
   * @param account The Agent's current Account with this specific Pool
   * @param vc The (pre-authorized) agent credential used to calculate the `maxBorrow` amount
   */
function beforeBorrow(
    uint256 borrowAsk,
    uint256 powerTokenStake,
    Account memory account,
    VerifiableCredential memory vc
  ) external pure {}

  /**
   * @dev A hook that gets called before exiting
   * @param exitAmount The amount of assets the Agent is returning
   * @param account The Agent's current Account with this specific Pool
   * @param vc The (pre-authorized) agent credential used to calculate the `maxBorrow` amount
   */
  function beforeExit(
      uint256 exitAmount,
      Account memory account,
      VerifiableCredential memory vc
  ) external pure {}

  /**
   * @dev A hook that gets called before making a payment
   * @param paymentAmount The payment amount
   * @param account The Agent's current account with this specific Pool
   */
  function beforeMakePayment(
      uint256 paymentAmount,
      Account memory account
  ) external pure {}

  /**
   * @dev A hook that gets called before making a payment
   * @param paymentAmount The desired amount to borrow to make a payment
   * @param powerTokenAmount The amount of power tokens that would be pledged to this Pool for a payment
   * @param account The Agent's current account with this specific Pool
   */
  function beforeStakeToPay(
      uint256 paymentAmount,
      uint256 powerTokenAmount,
      Account memory account
  ) external pure {}
}
