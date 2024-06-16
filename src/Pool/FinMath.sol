// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

library FinMath {
    using FixedPointMathLib for uint256;
    using Credentials for VerifiableCredential;

    // debt is the accumulation of interest + principal on the account
    function computeDebt(Account memory account, uint256 rate) internal view returns (uint256) {
        (uint256 _interestOwed,) = interestOwed(account, rate);
        return account.principal + _interestOwed;
    }

    function computeDTE(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        view
        returns (uint256 dte, uint256 debt, uint256 equity)
    {
        debt = computeDebt(account, rate);
        uint256 agentTotalValue = vc.getAgentValue(credParser);
        // if the agent's debt is greater than the entire value of the agent, the DTE is infinite
        if (debt >= agentTotalValue) return (type(uint256).max, debt, 0);
        equity = agentTotalValue - debt;
        // DTE = debt / equity
        return (debt.divWadDown(equity), debt, equity);
    }

    function computeDTI(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        pure
        returns (uint256 dti, uint256 dailyRate, uint256 dailyRewards)
    {
        // compute the daily expected payment owed by the agent based on current principal
        dailyRate = account.principal.mulWadUp(rate).mulWadUp(EPOCHS_IN_DAY);
        dailyRewards = vc.getExpectedDailyRewards(credParser);
        // if the agent's daily rewards are 0, the DTI is infinite
        if (dailyRewards == 0) return (type(uint256).max, dailyRate, dailyRewards);
        // DTI = daily rate / daily rewards
        return (dailyRate.divWadUp(dailyRewards), dailyRate, dailyRewards);
    }

    function computeDTL(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        view
        returns (uint256 dtl, uint256 debt, uint256 liquidationValue)
    {
        // compute the interest owed on the principal to add to principal to get total debt
        debt = computeDebt(account, rate);
        // confusing naming convention - "collateral value" == "liquidation value" in this context
        liquidationValue = vc.getCollateralValue(credParser);
        // if there is no debt, DTL is 0
        if (debt == 0) return (0, debt, liquidationValue);
        // if liquidation value is 0 (and there is debt), the DTL is infinite
        if (liquidationValue == 0) return (type(uint256).max, debt, liquidationValue);
        // DTL = debt / liquidation value
        return (debt.divWadDown(liquidationValue), debt, liquidationValue);
    }

    /// @dev returns the interest owed of a particular Account struct given a VerifiableCredential
    function interestOwed(Account memory account, uint256 rate)
        internal
        view
        returns (uint256 _totalInterest, uint256 _interestPerEpoch)
    {
        // compute the number of epochs that are owed to get current
        uint256 epochsToPay = block.number - account.epochsPaid;
        // multiply the rate by the principal to get the per epoch interest rate
        // the interestPerEpoch has an extra WAD to maintain precision
        _interestPerEpoch = interestPerEpoch(account, rate);
        // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
        // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
        return (_interestPerEpoch.mulWadUp(epochsToPay), _interestPerEpoch);
    }

    /// @dev returns the interest owed per epoch of a particular Account based on its principal
    function interestPerEpoch(Account memory account, uint256 rate) internal pure returns (uint256) {
        return account.principal.mulWadUp(rate);
    }
}

/// @dev a simple helper library for dealing with reward accrual
/// used to track treasury and LP rewards
library AccrualMath {
    error OverMath(uint256 paid, uint256 accrued, uint256 diff);

    function accrue(RewardAccrual memory ra, uint256 newAccruedRewards) internal pure returns (RewardAccrual memory) {
        ra.accrued += newAccruedRewards;
        return ra;
    }

    function payout(RewardAccrual memory ra, uint256 paidOutRewards) internal pure returns (RewardAccrual memory) {
        ra.paid += paidOutRewards;
        return ra;
    }

    function writeoff(RewardAccrual memory ra, uint256 lostRewards) internal pure returns (RewardAccrual memory) {
        ra.lost += lostRewards;
        return ra;
    }

    function owed(RewardAccrual memory ra) internal pure returns (uint256) {
        // in certain rounding edge cases, ra.paid can be tiny dust bits bigger than ra.accrued
        // the rounding errors should never exceed 1e2 - see testing invariants
        if (ra.paid + ra.lost >= ra.accrued) return 0;
        return ra.accrued - ra.paid - ra.lost;
    }
}
