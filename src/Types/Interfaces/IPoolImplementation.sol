// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";

interface IPoolImplementation {
    function getRate(
        uint256 borrowAsk,
        uint256 powerTokenStake,
        uint256 windowLength,
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (uint256);

    function rateSpike(
        uint256 penaltyEpochs,
        uint256 windowLength,
        Account memory account
    ) external view returns (uint256);

    function minCollateral(
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            Optional hooks
    //////////////////////////////////////////////////////////////*/

    function beforeBorrow(
        uint256 borrowAsk,
        uint256 powerTokenStake,
        Account memory account,
        VerifiableCredential memory vc
    ) external view;

    function beforeExit(
        uint256 exitAmount,
        Account memory account,
        VerifiableCredential memory vc
    ) external view;

    function beforeMakePayment(
        uint256 paymentAmount,
        Account memory account
    ) external view;

    function beforeStakeToPay(
        uint256 paymentAmount,
        uint256 powerTokenAmount,
        Account memory account
    ) external view;
}
