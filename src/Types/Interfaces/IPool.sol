// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
interface IPool  {

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
    function getAgentBorrowed(address agent) external view returns (uint256);
    function getAgentBorrowed(Account memory account) external view returns (uint256);
    function pmtPerPeriod(address agent) external view returns (uint256);
    function pmtPerPeriod(Account memory account) external view returns (uint256);
    function totalAssets() external view returns (uint256);
    function getPowerToken() external view returns (IPowerToken);
    // Would love to expose the public getter but not sure how to with the interitance structure we have
    function getAsset() external view returns (ERC20);
    function getAccount(address agent) external view returns (Account calldata);
    function setAccount(Account memory account, address owner) external;
    function resetAccount(address owner) external;
    function reduceTotalBorrowed(uint256 amount) external;
    function increaseTotalBorrowed(uint256 amount) external;
    // Finance functions
    function borrow(
        uint256 amount,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    ) external returns (uint256);
    function exitPool(
        address agent,
        SignedCredential memory sc,
        uint256 amount
    ) external returns (uint256);
    function makePayment(
        address agent,
        uint256 amount
    ) external;
    // Admin Funcs
    function flush() external;
}

