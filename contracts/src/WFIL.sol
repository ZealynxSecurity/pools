// SPDX-License-Identifier: UNLICENSED
// from https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code

pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

contract WFIL is ERC20 {
    using SafeTransferLib for ERC20;

    event  Deposit(address indexed dst, uint256 wad);
    event  Withdrawal(address indexed src, uint256 wad);

    constructor(
    ) ERC20("Wrapped Filecoin", "WFIL", 18) {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}
