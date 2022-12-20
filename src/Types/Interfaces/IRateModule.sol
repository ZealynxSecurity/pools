// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

interface IRateModule {
    function getRate(VerifiableCredential memory vc, uint256 amount) external view returns (uint256);
}
