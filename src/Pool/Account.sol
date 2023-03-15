// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {InsufficientPayment, InvalidParams} from "src/Errors.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

library AccountHelpers {
  using FixedPointMathLib for uint256;

  /*////////////////////////////////////////////////////////
                        Agent Utils
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Converts agent address to its ID
   */
  function agentAddrToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  /*////////////////////////////////////////////////////////
                      Account Getters
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Gets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the address of the agent
   * @param poolID the pool ID
   */
  function getAccount(
    address router,
    address agent,
    uint256 poolID
  ) internal view returns (Account memory) {
    return getAccount(router, agentAddrToID(agent), poolID);
  }

  /**
   * @dev Gets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agentID the agent's ID
   * @param poolID the pool ID
   */
  function getAccount(
    address router,
    uint256 agentID,
    uint256 poolID
  ) internal view returns (Account memory) {
    return IRouter(router).getAccount(agentID, poolID);
  }

  /**
   * @dev Returns true if an account exists
   */
  function exists(
    Account memory account
  ) internal pure returns (bool) {
    return account.startEpoch != 0;
  }

  /*////////////////////////////////////////////////////////
                      Account Setters
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Sets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the agent's address
   * @param poolID the pool ID
   */
  function setAccount(
    address router,
    address agent,
    uint256 poolID,
    Account memory account
  ) internal {
    setAccount(router, agentAddrToID(agent), poolID, account);
  }

  /**
   * @dev Sets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agentID the agent's ID
   * @param poolID the pool ID
   */
  function setAccount(
    address router,
    uint256 agentID,
    uint256 poolID,
    Account memory account
  ) internal {
    IRouter(router).setAccount(agentID, poolID, account);
  }

  /**
   * @dev Resets an account to default values
   *
   * in order to mutate the account, we have to manually reset all values,
   * instead of setting the account to be a new instance of an empty Account struct
   */
  function reset(Account memory account) internal pure {
    account.startEpoch = 0;
    account.totalBorrowed = 0;
    account.powerTokensStaked = 0;
    account.epochsPaid = 0;
    account.perEpochRate = 0;
    account.rateAdjEpoch = 0;
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
  ) internal view returns (uint256) {
    account.epochsPaid += getEpochsCredit(account, payment);
    return account.epochsPaid;
  }

  /**
   * @dev credits an account after a payment when the Account is in the penalty zone
   *
   * @param account the account to update
   * @param payment the amount of FIL that the agent paid
   * @param penaltyEpochs the number of epochs that the agent is in the penalty zone
   * @param penaltyRate the rateSpke the agent pays while in the penalty zone
   * @return epochsPaid the amount of epoch credit granted to the account
   */
  function creditInPenalty(
    Account memory account,
    uint256 payment,
    uint256 penaltyEpochs,
    uint256 penaltyRate
  ) internal view returns (uint256) {
    account.epochsPaid += getEpochsPenalty(
      account,
      payment,
      penaltyEpochs,
      penaltyRate
    );

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
    account.rateAdjEpoch = block.number;

    // fresh account, set start epoch and epochsPaid to beginning of current window
    if (account.totalBorrowed == 0) {
      account.startEpoch = block.number;
      account.epochsPaid = window.start;
    }

    account.totalBorrowed += askAmount;
    account.powerTokensStaked += powerTokenStake;

    return account.perEpochRate;
  }

  /**
   * @dev Saves an account in storage for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the agent's address
   * @param poolID the pool ID
   */
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

  /**
   * @dev Computes the minimum payment amount for a given window period
   */
  function pmtPerPeriod(
    Account memory account,
    address router
  ) internal view returns (uint256) {
    return pmtPerEpoch(account) * GetRoute.agentPolice(router).windowLength();
  }

  /**
   * @dev Computes the minimum payment amount for a single epoch
   */
  function pmtPerEpoch(Account memory account) internal pure returns (uint256) {
    return pmtPerEpoch(account, account.perEpochRate);
  }

  /**
   * @dev computes the minimum payment amount for a single penalty epoch
   * @param rateSpike - the additional rate to apply to the regular perEpochRate
   */
  function pmtPerPenaltyEpoch(
    Account memory account,
    uint256 rateSpike
  ) internal pure returns (uint256) {
    return pmtPerEpoch(account, account.perEpochRate + rateSpike);
  }

  /**
   * @dev computes the minimum payment amount for a singel epoch
   * @notice we divide out the 1e18 WAD base to get a % rate
   */
  function pmtPerEpoch(Account memory account, uint256 rate) internal pure returns (uint256) {
    return account.totalBorrowed
      .mulWadDown(rate);
  }

  /**
   * @dev computes the number of FIL needed to pay in order to bring an account to a deficit of 0,
   * meaning the account is "current" and epochsPaid is the start of the current window period
   *
   * @notice we divide out the 1e18 WAD base to get a % rate
   */
  function getDeficit(
    Account memory account,
    Window memory window,
    IPoolImplementation pool
  ) internal view returns (uint256 deficit) {
    // if the account is current, there is no deficit
    if (account.epochsPaid + window.length >= window.deadline) {
      return 0;
    }

    uint256 penaltyEpochs = getPenaltyEpochs(account, window);

    if (penaltyEpochs > 0) {
      uint256 rateSpike = pool.rateSpike(
        penaltyEpochs,
        window.length,
        account
      );

      uint256 perEpochPmtWPenalty = pmtPerPenaltyEpoch(account, rateSpike);
      // deficit starts at the penalty payment that you owe to get you to the start of the last window
      uint256 maxPenaltyPayment = perEpochPmtWPenalty * penaltyEpochs;
      deficit = maxPenaltyPayment;
    }

    // we add in the last window's missed payments
    uint256 totalMissedEpochs = window.start - account.epochsPaid;
    // take the minimum of the missed epochs and the window length
    // since the penaltyEpochs covered the missed epochs from _before_ the last window start
    uint256 unaccountedMissedEpochs = Math.min(
      totalMissedEpochs,
      window.length
    );

    deficit += pmtPerEpoch(account) * unaccountedMissedEpochs;
  }

  /**
   * @dev Computes the number of epochsPaid forward that a payment will bring an account
   * @param payment - The amount of payment to credit
   * @return epochs - THe amount of epochs to credit
   */
  function getEpochsCredit(
    Account memory account,
    uint256 payment
  ) internal view returns (uint256) {
    uint256 perEpochPmt = pmtPerEpoch(account);
    _amountGt(payment, perEpochPmt);
    return payment / perEpochPmt;
  }

  /**
   * @dev Computes the number of epochs that an Account is in penalty for
   *
   * @notice this is the number of epochs behind the _last_ window's open
   * the paymentPerEpoch must apply the rateSpike to this number of epochs
   */
  function getPenaltyEpochs(
    Account memory account,
    Window memory window
  ) internal pure returns (uint256) {
    // the penalty start is the last window's open
    uint256 penaltyStart = window.start - window.length;
    if (account.epochsPaid < penaltyStart) {
      return penaltyStart - account.epochsPaid;
    } else {
      return 0;
    }
  }


  /**
   * @dev Computes the amount of epochs to move an in penalty agent forward for a given payment
   * @param payment - The payment to compute epochs for
   * @param penaltyEpochs - The amount of epochs in penantly this `account` is
   * @param penaltyRate - The penalty rate to apply to the payment
   * @return epochs - The number of epochs to move the account forward
   */
  function getEpochsPenalty(
    Account memory account,
    uint256 payment,
    uint256 penaltyEpochs,
    uint256 penaltyRate
  ) internal view returns (uint256) {
    // first we apply the payment to the penalty epochs
    uint256 perEpochPmtWPenalty = pmtPerPenaltyEpoch(account, penaltyRate);
    _amountGt(payment, perEpochPmtWPenalty);

    uint256 maxPenaltyPayment = perEpochPmtWPenalty * penaltyEpochs;

    return payment <= maxPenaltyPayment
      // the payment only covers penalties
      ? payment / perEpochPmtWPenalty
      // the payment paid off the full penalty, and has more payment left to credit
      : penaltyEpochs + getEpochsCredit(account, payment - maxPenaltyPayment);
  }

  /**
   * @dev Computes the min payment to close the current window, using the existing rate in the account
   */
  function getMinPmtForWindowClose(
    Account memory account,
    Window memory window,
    address router,
    IPoolImplementation pool
  ) internal view returns (uint256) {
    // to get the window close, we add 1 to the deadline to avoid off by one errors with rounding
    return _getMinPmtForEpochCursor(
      account,
      window.deadline,
      router,
      window,
      pool
    );
  }

  /**
   * @dev Computes the min payment to get current, using the existing rate in the account
   */
  function getMinPmtForWindowStart(
    Account memory account,
    Window memory window,
    address router,
    IPoolImplementation pool
  ) internal view returns (uint256) {
    return _getMinPmtForEpochCursor(
      account,
      window.start,
      router,
      window,
      pool
    );
  }

  /**
   * @dev given an `epochValue`, compute the min payment (less fees) to get `account.epochsPaid === epochValue`
   * pass this amount as the `pmt` param in `makePayment`
   * @param account the account to compute the minimum payment target for
   * @param epochValue the epochValue represented the window that this payment will bring the account up to
   * @param router the router address to access global elements
   * @param window the current global window that the cursor is relative to
   * @param pool the pool implementation to access the rateSpike function
   */
  function _getMinPmtForEpochCursor(
    Account memory account,
    uint256 epochValue,
    address router,
    Window memory window,
    IPoolImplementation pool
  ) internal view returns (uint256 payment) {
    // if account is already paid up to that epoch, return 0
    if (account.epochsPaid >= epochValue) {
      return 0;
    }

    // Otherwise we need to bring account.epochsPaid up to epochValue

    // Anything before the start of the CURRENT window based on global window is in penalty
    uint256 penaltyStart = window.start - window.length;
    // We want to seperate the epochs into two bucckets

    // The first bucket is the epochs in penatly. These get a rate spike ADDED to their pool rate
    uint256 epochsPenalty;

    // The second bucket is the epochs after the penalty. These only have the treasury fee applied
    uint256 epochsRegular;

    // if the epochValue were moving the cursor to is within the penalty window, we only apply the penalty rate
    if (epochValue <= penaltyStart) {
      // The penalty is the cursor target minus the current account cursor position
      epochsPenalty = epochValue - account.epochsPaid;
    } else {
      bool inPenalty = account.epochsPaid < penaltyStart;

      // otherwise we get all the penalty epochs (if in penalty)
      epochsPenalty = inPenalty
        // add 1 to ensure we include the penaltyStart epoch
        ? penaltyStart - account.epochsPaid + 1
        : 0;

      // and the epochs up to the epochValue
      epochsRegular = epochValue - (inPenalty ? penaltyStart : account.epochsPaid);
    }


    // the amount (before fees), that the account owes to get to the epochValue
    uint256 basis;

    // add the penalty epochs
    basis += epochsPenalty * pmtPerPenaltyEpoch(account, pool.rateSpike(
        epochsPenalty,
        window.length,
        account
      ));
    // add the regular epochs
    basis += epochsRegular * pmtPerEpoch(account);

    // pmt = basis / (1 - fee)
    payment = basis.divWadUp(FixedPointMathLib.WAD - GetRoute.poolFactory(router).treasuryFeeRate());
  }

  /**
   * @dev Computes the treasury fee for a given payment
   * @param pmt - the payment amount
   * @param treasuryFeeRate - the treasury fee rate
   * @return fee - the fee amount
   */
  function computeFeePerPmt(
    Account memory,
    uint256 pmt,
    uint256 treasuryFeeRate
  ) internal pure returns (uint256 fee, uint256 remainingPmt) {
    // protocol fee * pmt
    fee = treasuryFeeRate.mulWadUp(pmt);
    // 900000000
    remainingPmt = pmt - fee;


  }

  function _amountGt(uint256 amount, uint256 minSize) internal view {
    if (amount < minSize) {
      revert InsufficientPayment(
        address(this),
        msg.sender,
        amount,
        minSize,
        msg.sig,
        "Pool: Payment size too small"
      );
    }
  }
}
