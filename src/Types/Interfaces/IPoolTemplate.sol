// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {PoolToken} from "src/Pool/PoolToken.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
interface IPoolTemplate  {

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Borrow(
        address indexed agent,
        uint256 amount,
        uint256 powerTokenAmount,
        uint256 rate
    );

    event Flush(
        address indexed caller,
        address indexed treasury,
        uint256 amount
    );

    event ExitPool(
        address indexed agent,
        uint256 amount,
        uint256 powerTokensReturned
    );

    event MakePayment(
        address indexed agent,
        uint256 pmt
    );

    event StakeToPay(
        address indexed agent,
        uint256 pmt,
        uint256 powerTokenAmount,
        uint256 newRate
    );

    // Finance functions
    function borrow(
        uint256 ask,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IPoolImplementation broker,
        Account memory account
    ) external returns (uint256);

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        Account memory account
    ) external returns (uint256 powerTokensToReturn);

    function makePayment(
        address agent,
        Account memory account,
        uint256 pmtLessFees
    ) external;

    function stakeToPay(
        uint256 borrowAmount,
        uint256 pmtLessFees,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IPoolImplementation broker,
        Account memory account
    ) external;

    function deposit(
        uint256 assets,
        address receiver,
        PoolToken share,
        ERC20 asset
    ) external returns (uint256 shares);

    function mint(
        uint256 shares,
        address receiver,
        PoolToken share,
        ERC20 asset
    ) external returns (uint256 assets);



    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        PoolToken share,
        PoolToken iou
    ) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        PoolToken share,
        PoolToken iou
    ) external  returns (uint256 assets);
}

