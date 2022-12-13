// SPDX-License-Identifier: UNLICENSED
// from https://etherscan.io/address/0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2#code

pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import "src/Agent/Agent.sol";

contract PowerToken is ERC20("Tokenized Filecoin Power", "POW", 18) {
    using SafeTransferLib for address;

    /*/////////////////////////////////
                EVENTS
    /////////////////////////////////*/
    event MintPower(address indexed agent, uint256 amount);
    event BurnPower(address indexed agent, uint256 amount);

    // TODO: Only registered agents can mint/burn
    function mint(uint256 _amount) public virtual {
      _mint(msg.sender, _amount);
      emit MintPower(msg.sender, _amount);
    }

    function burn(uint256 _amount) public virtual {
      _burn(msg.sender, _amount);
      emit BurnPower(msg.sender, _amount);
    }
}
