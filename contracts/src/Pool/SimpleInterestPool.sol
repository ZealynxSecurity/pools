// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "./IPool4626.sol";

contract SimpleInterestPool is IPool4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 poolID,
        uint256 baseRate,
        address treasury
    ) IPool4626(_asset, _name, _symbol, poolID, baseRate, treasury) {}
}
