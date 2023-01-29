// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {IPoolTokenPlus} from "src/Types/Interfaces/IPoolTokenPlus.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";

contract PoolToken is IPoolTokenPlus, RouterAware, ERC20 {
    uint256 public poolID;

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requiresAuth() {
        AuthController.onlyPoolAccounting(router, address(GetRoute.pool(router, poolID)));
        _;
    }

    constructor(
        address _router,
        uint256 _poolID,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) {
        router = _router;
        poolID = _poolID;
    }

    /*//////////////////////////////////////////////////////////////
                            MINT/BURN TOKENS
    //////////////////////////////////////////////////////////////*/

    function mint(
        address account,
        uint256 _amount
    ) public requiresAuth returns (bool) {
      _mint(account, _amount);
      return true;
    }

    function burn(
        address account,
        uint256 _amount
    ) public returns (bool) {
      _burn(account, _amount);
      return true;
    }
}
