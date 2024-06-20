// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20} from "src/Types/Interfaces/IERC20.sol";

interface IERC20Burnable {
    function burn(uint256 value) external;
    function burnFrom(address account, uint256 value) external;
}
