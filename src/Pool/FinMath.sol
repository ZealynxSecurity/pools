// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

library FinMath {
    using FixedPointMathLib for uint256;
    using Credentials for VerifiableCredential;

    // debt is the accumulation of interest + principal on the account
    function computeDebt(Account memory account, uint256 rate) internal view returns (uint256) {
        return account.principal + _interestOwed(account, rate);
    }

    function computeDTE(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        view
        returns (uint256)
    {
        uint256 debt = computeDebt(account, rate);
        uint256 agentTotalValue = vc.getAgentValue(credParser);
        // if the agent's debt is greater than the entire value of the agent, the DTE is infinite
        if (debt >= agentTotalValue) return type(uint256).max;
        uint256 equity = agentTotalValue - debt;
        // DTE = debt / equity
        return debt.divWadDown(equity);
    }

    function computeDTI(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        pure
        returns (uint256)
    {
        // compute the daily expected payment owed by the agent based on current principal
        uint256 dailyRate = account.principal.mulWadUp(rate).mulWadUp(EPOCHS_IN_DAY);
        uint256 dailyRewards = vc.getExpectedDailyRewards(credParser);
        // if the agent's daily rewards are 0, the DTI is infinite
        if (dailyRewards == 0) return type(uint256).max;
        // DTI = daily rate / daily rewards
        return dailyRate.divWadUp(dailyRewards);
    }

    function computeDTL(Account memory account, VerifiableCredential calldata vc, uint256 rate, address credParser)
        internal
        view
        returns (uint256)
    {
        // compute the interest owed on the principal to add to principal to get total debt
        uint256 debt = computeDebt(account, rate);
        // confusing naming convention - "collateral value" == "liquidation value" in this context
        uint256 liquidationValue = vc.getCollateralValue(credParser);
        // if there is no debt, DTL is 0
        if (debt == 0) return 0;
        // if liquidation value is 0 (and there is debt), the DTL is infinite
        if (liquidationValue == 0) return type(uint256).max;
        // DTL = debt / liquidation value
        return debt.divWadDown(liquidationValue);
    }

    /// @dev returns the interest owed of a particular Account struct given a VerifiableCredential
    function _interestOwed(Account memory account, uint256 rate) internal view returns (uint256) {
        // compute the number of epochs that are owed to get current
        uint256 epochsToPay = block.number - account.epochsPaid;
        // multiply the rate by the principal to get the per epoch interest rate
        // the interestPerEpoch has an extra WAD to maintain precision
        uint256 interestPerEpoch = account.principal.mulWadUp(rate);
        // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
        // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
        return interestPerEpoch.mulWadUp(epochsToPay);
    }
}
