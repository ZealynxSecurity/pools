// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Account} from "src/Types/Structs/Account.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {InvalidParams} from "src/Errors.sol";

library AccountHelpers {
  using FixedPointMathLib for uint256;

  /*////////////////////////////////////////////////////////
                        Agent Utils
  ////////////////////////////////////////////////////////*/

  function agentAddrToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  /*////////////////////////////////////////////////////////
                      Account Getters
  ////////////////////////////////////////////////////////*/

  function getAccount(
    address router,
    address agent,
    uint256 poolID
  ) internal view returns (Account memory) {
    return getAccount(router, agentAddrToID(agent), poolID);
  }

  function getAccount(
    address router,
    uint256 agentID,
    uint256 poolID
  ) internal view returns (Account memory) {
    return IRouter(router).getAccount(agentID, poolID);
  }

  function exists(
    Account memory account
  ) internal pure returns (bool) {
    return account.startEpoch != 0;
  }

  /*////////////////////////////////////////////////////////
                      Account Setters
  ////////////////////////////////////////////////////////*/

  function setAccount(
    address router,
    address agent,
    uint256 poolID,
    Account memory account
  ) internal {
    setAccount(router, agentAddrToID(agent), poolID, account);
  }

  function setAccount(
    address router,
    uint256 agentID,
    uint256 poolID,
    Account memory account
  ) internal {
    IRouter(router).setAccount(agentID, poolID, account);
  }

  // in order to mutate the account, we have to manually reset all values (instead of setting the account to be a new instance of an empty Account struct)
  function reset(Account memory account) internal pure {
    account.startEpoch = 0;
    account.totalBorrowed = 0;
    account.powerTokensStaked = 0;
    account.epochsPaid = 0;
    account.perEpochRate = 0;
  }

  /**
   * @dev credits an account after a payment
   *
   * @param account the account to update
   * @param payment the amount of FIL that the agent paid
   * @return epochsPaid the amount of epoch credit granted to the account
   */
  function credit(
    Account memory account,
    uint256 payment
  ) internal pure returns (uint256) {
    account.epochsPaid += getEpochsCredit(account, payment);
    return account.epochsPaid;
  }

  /**
   * @dev updates an account after exit
   *
   * @param account the account to update
   * @param returnedFILAmt the amount of FIL that the agent wishes to exit
   * @return powerTokensToReturn the amount of power tokens that must be returned to the agent
   */
  function exit(
    Account memory account,
    uint256 returnedFILAmt
  ) internal pure returns (
    uint256 powerTokensToReturn
  ) {
    // if the returned FIL amount is the total amount borrowed, the agent has completely exited their position from the associated pool, so we return all power tokens
    if (returnedFILAmt == account.totalBorrowed) {
      powerTokensToReturn = account.powerTokensStaked;
      reset(account);
    } else {
      // compute the % of power tokens to return
      powerTokensToReturn =
        returnedFILAmt * account.powerTokensStaked / account.totalBorrowed;

      account.powerTokensStaked -= powerTokensToReturn;
      account.totalBorrowed -= returnedFILAmt;
    }
  }

  /**
   * @dev updates an account after borrow
   *
   * @param account the account to update
   * @param router the router address
   * @param askAmount the amount of FIL that the agent wishes to borrow
   * @param pool an instance of an IPoolImplementation to call getRate from
   * @return perEpochRate the rate gotten by the agent
   */
  function borrow(
    Account memory account,
    address router,
    uint256 askAmount,
    uint256 powerTokenStake,
    VerifiableCredential memory vc,
    IPoolImplementation pool
  ) internal view returns (uint256 perEpochRate) {
    Window memory window = GetRoute.agentPolice(router).windowInfo();
    account.perEpochRate = pool.getRate(
      askAmount,
      powerTokenStake,
      window.length,
      account,
      vc
    );

    // fresh account, set start epoch and epochsPaid to beginning of current window
    if (account.totalBorrowed == 0) {
      account.startEpoch = block.number;
      account.epochsPaid = window.start;
    }

    account.totalBorrowed += askAmount;
    account.powerTokensStaked += powerTokenStake;

    return account.perEpochRate;
  }

  function save(
    Account memory account,
    address router,
    address agent,
    uint256 poolID
  ) internal {
    setAccount(router, agent, poolID, account);
  }

  /*////////////////////////////////////////////////////////
                  Computed Account Statistics
  ////////////////////////////////////////////////////////*/

  /// @dev computes the minimum payment amount for a given window period
  function pmtPerPeriod(
    Account memory account,
    address router
  ) internal view returns (uint256) {
    return pmtPerEpoch(account) * GetRoute.agentPolice(router).windowLength();
  }

  /// @dev computes the minimum payment amount for a singel epoch
  /// @notice we divide out the 1e18 WAD base to get a % rate
  function pmtPerEpoch(Account memory account) internal pure returns (uint256) {
    return account.totalBorrowed
      .mulWadDown(account.perEpochRate);
  }

  /// @dev computes the number of FIL needed to pay in order to bring an account to a deficit of 0 (meaning the account is "current" and epochsPaid is the start of the current window period)
  function getDeficit(
    Account memory account,
    Window memory window
  ) internal pure returns (uint256) {
      uint256 deficit;
      // account has a deficit
      if (account.epochsPaid + window.length < window.deadline) {
          uint256 epochsDeficit = window.deadline - window.length - account.epochsPaid;
          deficit = epochsDeficit * pmtPerEpoch(account);
      }

      return deficit;
  }

  /// @dev computes the number of epochsPaid forward that a payment will bring an account
  function getEpochsCredit(
    Account memory account,
    uint256 payment
  ) internal pure returns (uint256) {

    // if we use divWadUp here, we get off by one errors (short) with rounding
    return payment / (pmtPerEpoch(account));
  }

  /// @dev computes the min payment to close the current window, using the existing rate in the account
  function getMinPmtForWindowClose(
    Account memory account,
    Window memory window,
    address router,
    IPoolImplementation pool
  ) internal view returns (uint256) {
    // to get the window close, we add 1 to the deadline to avoid off by one errors with rounding
    return _getMinPmtForEpochCursor(account, window.deadline + 1, router, pool);
  }

  /// @dev computes the min payment to get current, using the existing rate in the account
  function getMinPmtForWindowStart(
    Account memory account,
    Window memory window,
    address router,
    IPoolImplementation pool
  ) internal view returns (uint256) {
    return _getMinPmtForEpochCursor(account, window.start + 1, router, pool);
  }

  /// @dev given an `epochValue`, compute the min payment (less fees) to get `account.epochsPaid === epochValue`
  /// pass this amount as the `pmt` param in `makePayment`
  /// @notice you can use this function to compute the `stakeToPay` pmt amount,
  /// but it's not quite as accurate for epochValues past window.start of the current period
  /// (since stakeToPay will give you a new rate)
  function _getMinPmtForEpochCursor(
    Account memory account,
    uint256 epochValue,
    address router,
    // TODO: Add penalties
    IPoolImplementation
  ) internal view returns (uint256) {
    // if account is already paid up to that epoch, return 0
    if (account.epochsPaid >= epochValue) {
      return 0;
    }

    uint256 fee = _computeProtocolFee(
      account,
      GetRoute.poolFactory(router).treasuryFeeRate()
    );

    // pmt = epochsToPay * pmtPerEpoch * (1 + fee)
    return ( (epochValue - account.epochsPaid) * pmtPerEpoch(account) )
      .mulWadUp(
        fee + FixedPointMathLib.WAD
      );
  }

  function _computeProtocolFee(
    Account memory account,
    uint256 treasuryFeeRate
  ) internal pure returns (uint256) {
    // (treasury fee rate * pool pmt rate)
    uint256 denominator = treasuryFeeRate.mulWadUp(account.perEpochRate);

    // 1 / denominator
    return uint256(1).divWadUp(denominator);
  }

  function computeFeePerPmt(
    Account memory account,
    uint256 pmt,
    uint256 treasuryFeeRate
  ) internal pure returns (uint256 fee, uint256 remainingPmt) {
      // 1 / denominator
      uint256 protocolFee = _computeProtocolFee(account, treasuryFeeRate);

      // protocol fee * pmt
      fee = protocolFee.mulWadUp(pmt);

      remainingPmt = pmt - fee;
  }
}
