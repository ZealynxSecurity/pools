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
import {AccountHelpers} from "src/Pool/Account.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN, ROUTE_POOL_FACTORY} from "src/Constants/Routes.sol";
import {
    AccountDNE,
    InsufficientLiquidity,
    InsufficientPower,
    InsufficientPayment
} from "src/Errors.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

uint256 constant DUST = 1000;

/// NOTE: this pool uses accrual basis accounting to compute share prices
contract PoolTemplate is IPoolTemplate, RouterAware {
    using FixedPointMathLib for uint256;
    using AccountHelpers for Account;

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
        IPoolImplementation poolImpl,
        Account memory account
    ) public onlyAccounting returns (uint256) {
        IPool pool = IPool(msg.sender);
        // check
        _checkLiquidity(ask, pool.totalAssets());

        // TODO: require(amount <= vc.amount) https://github.com/glif-confidential/pools/issues/120

        account.borrow(
            router,
            ask,
            powerTokenAmount,
            vc,
            poolImpl
        );

        account.save(router, vc.subject, _id(msg.sender));

        pool.increaseTotalBorrowed(ask);

        emit Borrow(vc.subject, ask, account.perEpochRate, account.totalBorrowed);

        return account.perEpochRate;
    }

    // allows an agent to make a payment by staking more power
    /// NOTE: an agent can only stakeToPay if the staking brings the account current
    /// A pool implementation does not have to let this happen,
    /// a new call to getRate gets made, which can revert and end the entire operation
    function stakeToPay(
        uint256 borrowAmount,
        uint256 pmtLessFee,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IPoolImplementation poolImpl,
        Account memory account
    ) external onlyAccounting accountExists(vc.subject, account) {
        IPool pool = IPool(msg.sender);

        Window memory window = GetRoute.agentPolice(router).windowInfo();

        // uses the old rate to compute how much is owed up to the current window
        uint256 deficit = account.getDeficit(window);
        // ensure this payment can bring the account current
        _checkPaymentSize(pmtLessFee, deficit);
        // bring account current
        account.epochsPaid = window.start;
        /// @dev we get a new rate
        /// @notice the pool implementation may choose to not allow this in which case, stakeToPay will revert
        account.borrow(
            router,
            borrowAmount,
            powerTokenAmount,
            vc,
            poolImpl
        );
        // credit the account with any remaining payment leftover after getting out of deficit
        account.credit(pmtLessFee - deficit);
        account.save(router, vc.subject, _id(msg.sender));

        pool.increaseTotalBorrowed(borrowAmount);

        emit StakeToPay(
            vc.subject,
            borrowAmount,
            powerTokenAmount,
            account.perEpochRate
        );
    }

    function makePayment(
        address agent,
        Account memory account,
        uint256 pmtLessFees
    ) public onlyAccounting accountExists(agent, account) {
        _checkPaymentSize(pmtLessFees, account.perEpochRate);

        account.credit(pmtLessFees);
        account.save(router, agent, _id(msg.sender));

        emit MakePayment(agent, pmtLessFees);
    }

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        Account memory account
    ) public onlyAccounting accountExists(vc.subject, account) returns (uint256) {
        require(amount <= account.totalBorrowed, "Amount to exit must be less than the total borrowed");
        IPool pool = IPool(msg.sender);

        pool.reduceTotalBorrowed(amount);

        uint256 powerTokensToReturn = account.exit(amount);
        account.save(router, vc.subject, _id(msg.sender));

        emit ExitPool(vc.subject, amount, powerTokensToReturn);

        return powerTokensToReturn;
    }

    /*////////////////////////////////////////////////////////
                    ERC-4626 VAULT FUNCTIONS
    ////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver, PoolToken share, ERC20 asset) public virtual returns (uint256 shares) {
        IPool pool = IPool(msg.sender);
        // Check for rounding error since we round down in previewDeposit.
        require((shares = pool.previewDeposit(assets)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(ERC20(asset), receiver, msg.sender, assets);

        share.mint(receiver, shares);

        //emit Deposit(msg.sender, receiver, assets, shares);

    }

    function mint(uint256 shares, address receiver, PoolToken share, ERC20 asset) public virtual returns (uint256 assets) {
        IPool pool = IPool(msg.sender);
        // Check for rounding error since we round down in previewDeposit.
        require((assets = pool.previewMint(shares)) != 0, "ZERO_ASSETS");

        // Need to transfer before minting or ERC777s could reenter.
        SafeTransferLib.safeTransferFrom(ERC20(asset), receiver, msg.sender, assets);

        share.mint(receiver, shares);

        //emit Deposit(msg.sender, receiver, assets, shares);

    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        PoolToken share,
        ERC20 asset
    ) public virtual returns (uint256 shares) {
        IPool pool = IPool(msg.sender);
        shares = pool.previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        share.burn(owner, shares);

        //emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransferFrom(ERC20(asset), msg.sender, receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        PoolToken share,
        ERC20 asset
    ) public virtual returns (uint256 assets) {
        IPool pool = IPool(msg.sender);
        // TODO: store allowance once

        // Check for rounding error since we round down in previewRedeem.
        require((assets = pool.previewRedeem(shares)) != 0, "ZERO_ASSETS");

        share.burn(owner, shares);

        //emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransferFrom(ERC20(asset), msg.sender, receiver, assets);
    }

    /*////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////*/

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

    function _checkPaymentSize(uint256 amount, uint256 minSize) internal view {
        if (amount < minSize) {
            revert InsufficientPayment(
                address(this),
                msg.sender,
                amount,
                minSize,
                msg.sig,
                "PoolTemplate: Payment size too small"
            );
        }
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

    function _id(address pool) internal view returns (uint256) {
        return IPool(pool).id();
    }
}

