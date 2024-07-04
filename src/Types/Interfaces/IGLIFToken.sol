// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20Burnable} from "src/Types/Interfaces/IERC20Burnable.sol";
import {IERC20Votes} from "src/Types/Interfaces/IERC20Votes.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGLIFToken is IERC20, IERC20Burnable, IERC20Votes, IERC20Permit {
    function mint(address account, uint256 value) external;
    function cap() external view returns (uint256);
    function minter() external view returns (address);
    function setMinter(address _minter) external;
    function setCap(uint256 _cap) external;
}
