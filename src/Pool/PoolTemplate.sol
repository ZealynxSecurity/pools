// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {GetRoute} from "src/Router/GetRoute.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IBroker} from "src/Types/Interfaces/IBroker.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN, ROUTE_POOL_FACTORY} from "src/Constants/Routes.sol";
import {
    AccountDNE,
    InsufficientLiquidity,
    InsufficientPower
} from "src/Errors.sol";

uint256 constant DUST = 1000;

/// NOTE: this pool uses accrual basis accounting to compute share prices
contract PoolTemplate is IPoolTemplate, RouterAware {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////*/

    modifier onlyAccounting() {
        AuthController.onlyPoolAccounting(router, msg.sender);
        _;
    }

    modifier requiresAuth() {
        AuthController.requiresSubAuth(router, address(this));
        _;
    }

    modifier onlyAgent(address caller) {
        AuthController.onlyAgent(router, caller);
        _;
    }

    modifier accountExists(address agent, Account memory account) {
        _accountExists(agent, account, msg.sig);
        _;
    }

    /*////////////////////////////////////////////////////////
                      Pool Borrowing Functions
    ////////////////////////////////////////////////////////*/

    function borrow(
        uint256 ask,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IBroker broker,
        Account memory account
    ) public onlyAccounting returns (uint256) {
        IPool pool = IPool(msg.sender);
        // check
        _checkLiquidity(ask, pool.totalAssets());

        // TODO: require(amount <= vc.amount) https://github.com/glif-confidential/pools/issues/120

        // effects
        account.pmtPerPeriod = broker.getRate(vc, powerTokenAmount, account);
        uint256 currentTotal = account.totalBorrowed;
        account.totalBorrowed = currentTotal + ask;
        pool.increaseTotalBorrowed(ask);
        account.startEpoch = currentTotal == 0 ? block.number : account.startEpoch;
        account.powerTokensStaked = account.powerTokensStaked + powerTokenAmount;
        // NOTE: Worth validating that the sender is a pool? Probably handle this in roles or with a modifier - is the Pool on the VC? Maybe it should be
        pool.setAccount(account, vc.subject);

        emit Borrow(msg.sender, ask, account.pmtPerPeriod, account.totalBorrowed);

        return account.pmtPerPeriod;
    }

    // allows an agent to make a payment by staking more power
    /// NOTE: an agent can only stakeToPay if the staking brings the account current
    /// A pool implementation does not have to let this happen,
    /// a new call to getRate gets made, which can revert and end the entire operation
    function stakeToPay(
        uint256 pmt,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IBroker broker,
        Account memory account
    ) external onlyAccounting accountExists(vc.subject, account) {
        IPool pool = IPool(msg.sender);
        IAgentPolice police = GetRoute.agentPolice(router);

        uint256 windowLength = police.windowLength();
        uint256 nextWindowDeadline = police.nextPmtWindowDeadline();

        // uses the old rate
        uint256 deficit = _getDeficit(
            windowLength,
            nextWindowDeadline,
            account.pmtPerPeriod,
            account.epochsPaid
        );

        if (pmt < deficit) {
            revert InsufficientPower(
                address(this),
                vc.subject,
                pmt,
                deficit,
                msg.sig,
                "PoolTemplate: additional power insufficient to make payment to bring account current"
            );
        }

        account.epochsPaid = nextWindowDeadline - windowLength;

        // the pool implementation may decide not to give this agent more funds to make payments
        // the getRate function would revert in this case
        uint256 newRate = broker.getRate(vc, powerTokenAmount, account);

        // uses the new rate
        account.epochsPaid = _getEpochsCredit(
            pmt - deficit,
            newRate,
            windowLength
        );

        account.powerTokensStaked += powerTokenAmount;
        account.totalBorrowed += pmt;
        account.pmtPerPeriod = newRate;

        pool.increaseTotalBorrowed(pmt);
        pool.setAccount(account, vc.subject);

        emit StakeToPay(
            vc.subject,
            pmt,
            powerTokenAmount,
            newRate
        );
    }

    function makePayment(
        address agent,
        Account memory account,
        // TODO: use this
        uint256 pmt
    ) public onlyAccounting accountExists(agent, account) {
        IPool pool = IPool(msg.sender);
        uint256 windowLength = GetRoute.agentPolice(router).windowLength();
        /// @dev payment periods are accounted for in 1e18 basis to calculate precise epochs below the window length (fractions of window length) 1e18 === 1 period
        uint256 paymentPeriods = pmt.divWadDown(account.pmtPerPeriod);

        account.epochsPaid += paymentPeriods.mulWadDown(windowLength).divWadDown(FixedPointMathLib.WAD);
        pool.setAccount(account, agent);

        emit MakePayment(agent, pmt);
    }

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        IBroker broker,
        Account memory account
    ) public onlyAccounting accountExists(vc.subject, account) returns (uint256) {
        require(amount <= account.totalBorrowed, "Amount to exit must be less than the total borrowed");
        IPool pool = IPool(msg.sender);

        pool.reduceTotalBorrowed(amount);

        // The power tokens that must be returned to the pool is the same percent as the amount that the agent wishes to exit
        // TODO: Gas optimization: this could be done in one line if needed- less legible
        uint256 powerTokenAmount = amount * account.powerTokensStaked / account.totalBorrowed;
        uint256 powerTokensLeft = account.powerTokensStaked - powerTokenAmount;
        // fully paid off
        if (powerTokensLeft <= DUST) {
            pool.resetAccount(vc.subject);
            return account.powerTokensStaked;
        }

        account.powerTokensStaked = account.powerTokensStaked - powerTokenAmount;
        account.totalBorrowed = account.totalBorrowed - amount;
        // Get the new rate from the rate module
        account.pmtPerPeriod = broker.getRate(vc, account.powerTokensStaked, account);
        // Update the account information
        pool.setAccount(account, vc.subject);

        emit ExitPool(vc.subject, amount, powerTokenAmount);

        return powerTokenAmount;
    }

    function _checkLiquidity(uint256 amount, uint256 available) internal view {
        if (available <= amount) {
            revert InsufficientLiquidity(
                address(this),
                msg.sender,
                amount,
                available,
                msg.sig,
                "PoolTemplate: Insufficient liquidity"
            );
        }
    }

    function _getDeficit(
        uint256 windowLength,
        uint256 windowDeadline,
        uint256 pmtPerPeriod,
        uint256 epochsPaid
    ) internal pure returns (uint256) {
        uint256 existingPerPaymentEpoch = pmtPerPeriod.mulWadUp(windowLength*1e18);

        uint256 deficit;
        // account has a deficit
        if (epochsPaid + windowLength < windowDeadline) {
            uint256 epochsDeficit = windowDeadline - windowLength - epochsPaid;
            deficit = epochsDeficit * existingPerPaymentEpoch;
        }

        return deficit;
    }

    function _getEpochsCredit(
        uint256 pmt,
        uint256 newRate,
        uint256 windowLength
    ) internal pure returns (uint256) {
        // compute a per epoch payment from the new rate
        uint256 newPerPaymentEpoch = newRate.divWadUp(windowLength);
        return pmt.divWadDown(newPerPaymentEpoch);
    }

    function _accountExists(
        address agent,
        Account memory account,
        bytes4 sig
    ) internal pure returns (bool) {
        if (account.startEpoch == 0) {
            revert AccountDNE(
                agent,
                sig,
                "PoolTemplate: Account does not exist"
            );
        }

        return true;
    }
}

