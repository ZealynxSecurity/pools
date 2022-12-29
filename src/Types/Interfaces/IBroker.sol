// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";

interface IBroker {
    function getRate(VerifiableCredential memory vc, uint256 amount, Account memory account) external view returns (uint256);
}
