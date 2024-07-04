// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Token} from "src/Token/Token.sol";
import {PoolToken} from "shim/PoolToken.sol";
import "./EchidnaConfig.sol";

contract EchidnaSetup is EchidnaConfig {
    Token internal rewardToken;
    PoolToken internal lockToken;
    address internal _erc20rewardToken;
    address internal _erc20lockToken;

    constructor() {
        rewardToken = new Token("GLIF", "GLF", address(this), address(this));
        lockToken = new PoolToken(address(this));
        lockToken.setMinter(address(this));
        _erc20rewardToken = address(rewardToken);
        _erc20lockToken = address(lockToken);
    }
}
