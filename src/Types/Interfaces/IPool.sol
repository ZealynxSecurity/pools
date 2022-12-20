// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
interface IPool  {

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Borrow(
        address indexed caller,
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
        address indexed caller,
        address indexed agent,
        uint256 amount
    );

    event MakePayment(
        address indexed caller,
        address indexed agent,
        uint256 amount
    );

    // Basic Stats Getters **PURE**
    function nextDueDate(Account memory account) external view returns (uint256);
    function nextDueDate(address agent) external view returns (uint256);
    function getAgentBorrowed(address agent) external view returns (uint256);
    function getAgentBorrowed(Account memory account) external view returns (uint256);
    function pmtPerPeriod(address agent) external view returns (uint256);
    function pmtPerPeriod(Account memory account) external view returns (uint256);
    // Would love to expose the public getter but not sure how to with the interitance structure we have
    function getAsset() external view returns (IERC20);
    function getAccount(address agent) external view returns (Account calldata);
    // Finance functions
    function borrow(uint256 amount, address agent, VerifiableCredential memory vc, uint256 powerTokenAmount) external returns (uint256);
    function exitPool(uint256 amount, address agent, VerifiableCredential memory vc) external;
    function makePayment(address agent, VerifiableCredential memory vc) external;
    // Admin Funcs
    function flush() external;
}

