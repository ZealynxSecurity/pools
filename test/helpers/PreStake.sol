// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";

contract PreStake {
    IWFIL private wFIL;

    constructor(address, IWFIL _wFIL, IPoolToken) {
        wFIL = _wFIL;
    }

    function totalValueLocked() external view returns (uint256) {
        return wFIL.balanceOf(address(this)) + address(this).balance;
    }
}
