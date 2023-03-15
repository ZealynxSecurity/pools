// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN, ROUTE_POOL_FACTORY} from "src/Constants/Routes.sol";
import {
    AccountDNE,
    InsufficientLiquidity,
    InsufficientPower,
    InsufficientPayment,
    Unauthorized
} from "src/Errors.sol";

uint256 constant DUST = 1000;

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

    modifier onlyAgent(address caller) {
        AuthController.onlyAgent(router, caller);
        _;
    }

    modifier accountExists(address agent, Account memory account) {
        _accountExists(agent, account, msg.sig);
        _;
    }

    modifier accountNotInPenalty(address agent, Account memory account) {
        _accountNotInPenalty(agent, account);
        _;
    }

    modifier accountCurrent(address agent, Account memory account) {
        _accountCurrent(agent, account);
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
    ) public onlyAccounting accountNotInPenalty(vc.subject, account) returns (uint256) {
        IPool pool = IPool(msg.sender);
        // check
        _checkLiquidity(ask, pool.totalBorrowableAssets());

        if (ask > vc.cap) {
            revert Unauthorized();
        }

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

    function makePayment(
        address agent,
        Account memory account,
        uint256 pmtLessFees
    ) public onlyAccounting accountExists(agent, account) {
        Window memory window = GetRoute.agentPolice(router).windowInfo();
        uint256 penaltyEpochs = account.getPenaltyEpochs(window);

        if (penaltyEpochs > 0) {
            account.creditInPenalty(
                pmtLessFees,
                penaltyEpochs,
                IPool(msg.sender).implementation().rateSpike(
                    penaltyEpochs,
                    window.length,
                    account
                )
            );
        } else {
            account.credit(pmtLessFees);
        }

        account.save(router, agent, _id(msg.sender));

        emit MakePayment(agent, pmtLessFees);
    }


    /// @notice an Agent cannot exitPool unless their account is current
    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        Account memory account
    )
        public
        onlyAccounting
        accountCurrent(vc.subject, account)
        returns (uint256)
    {
        AccountHelpers._amountGt(account.totalBorrowed, amount);

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


    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        IPool pool = IPool(msg.sender);
        pool.share().mint(receiver, shares);
        assets = pool.convertToAssets(shares);
    }

    function deposit(uint256, address) public returns (uint256) {
        revert();
    }

    function filToAsset(ERC20 asset, address receiver) external payable returns (uint256) {
        IWFIL wFIL = GetRoute.wFIL(router);

        // in this Template, the asset must be wFIL
        require(
            address(asset) == address(wFIL),
            "Asset must be wFIL to deposit FIL"
        );
        // handle FIL deposit
        uint256 assets = msg.value;
        wFIL.deposit{value: assets}();
        wFIL.transfer(receiver, assets);
        return assets;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        PoolToken share,
        PoolToken iou
    ) public returns (uint256 shares) {
        IPool pool = IPool(msg.sender);
        shares = pool.previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        share.burn(owner, shares);

        // Handle minimum liquidity in case that PoolAccounting has sufficient balance to cover
        iou.mint(address(this), assets);
        iou.approve(address(pool.ramp()), assets);
        pool.ramp().stakeOnBehalf(assets, receiver);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        PoolToken share,
        PoolToken iou
    ) public virtual returns (uint256 assets) {
        IPool pool = IPool(msg.sender);
        // TODO: store allowance once

        // Check for rounding error since we round down in previewRedeem.
        require((assets = pool.previewRedeem(shares)) != 0, "ZERO_ASSETS");

        share.burn(owner, shares);

        // Handle minimum liquidity in case that PoolAccounting has sufficient balance to cover
        iou.mint(address(this), assets);
        iou.approve(address(pool.ramp()), assets);
        pool.ramp().stakeOnBehalf(assets, receiver);
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

    function _accountExists(
        address agent,
        Account memory account,
        bytes4 sig
    ) internal pure returns (bool) {
        if (!account.exists()) {
            revert AccountDNE(
                agent,
                sig,
                "PoolTemplate: Account does not exist"
            );
        }

        return true;
    }

    function _accountCurrent(address agent, Account memory account) internal view returns (bool) {
        if (GetRoute.agentPolice(router).windowInfo().start > account.epochsPaid) {
            revert Unauthorized();
        }

        return true;
    }

    function _accountNotInPenalty(
        address agent,
        Account memory account
    ) internal view returns (bool) {
        if (account.getPenaltyEpochs(GetRoute.agentPolice(router).windowInfo()) > 0) {
            revert Unauthorized();
        }

        return true;
    }

    function _id(address pool) internal view returns (uint256) {
        return IPool(pool).id();
    }

}
