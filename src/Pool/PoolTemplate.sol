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
        require(ask <= pool.totalAssets(), "Amount to borrow must be less than this pool's liquid totalAssets");
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

        // accrual basis accounting
        emit Borrow(msg.sender, ask, account.pmtPerPeriod, account.totalBorrowed);

        return account.pmtPerPeriod;
    }

    // TODO: Accounting for flexible pmt amount https://github.com/glif-confidential/pools/issues/165?
    function makePayment(
        address agent,
        Account memory account,
        // TODO: use this
        uint256 pmt
    ) public onlyAccounting {
        IPool pool = IPool(msg.sender);
        // TODO: proper accounting
        pool.setAccount(account, agent);
    }

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        IBroker broker,
        Account memory account
    ) public onlyAccounting returns (uint256) {
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
        // Get the new rate from the rate module
        account.pmtPerPeriod = broker.getRate(vc, account.powerTokensStaked, account);
        // Update the account information
        pool.setAccount(account, vc.subject);

        return powerTokenAmount;
    }
}

