// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IPoolTokenPlus} from "src/Types/Interfaces/IPoolTokenPlus.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {ERC20} from "shim/ERC20.sol";

contract PoolToken is IPoolTokenPlus, ERC20, Ownable {
    address public minter;
    address public burner;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyBurner() {
        if (msg.sender != burner) {
            revert Unauthorized();
        }
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner
    ) ERC20(_name, _symbol, 18) Ownable(_owner) {}

    /*//////////////////////////////////////////////////////////////
                            MINT/BURN TOKENS
    //////////////////////////////////////////////////////////////*/

    function mint(
        address account,
        uint256 _amount
    ) external onlyMinter returns (bool) {
      _mint(account, _amount);
      return true;
    }

    function burn(
        address account,
        uint256 _amount
    ) external onlyBurner returns (bool) {
      _burn(account, _amount);
      return true;
    }
    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function setBurner(address _burner) external onlyOwner {
        burner = _burner;
    }
}
