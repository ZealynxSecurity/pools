// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IBroker} from "src/Types/Interfaces/IBroker.sol";

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
        IBroker broker,
        Account memory account
    ) external returns (uint256);

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc,
        IBroker broker,
        Account memory account
    ) external returns (uint256 powerTokensToReturn);

    function makePayment(
        address agent,
        Account memory account,
        uint256 pmt
    ) external;

    function stakeToPay(
        uint256 pmt,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount,
        IBroker broker,
        Account memory account
    ) external;
}

