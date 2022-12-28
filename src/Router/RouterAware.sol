// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AuthController} from "src/Auth/AuthController.sol";

abstract contract RouterAware {
  address public router;


  function setRouter(address _router) public {
    // we avoid the access control check if the router is not set yet
    if (router == address(0)) {
      router = _router;
      return;
    }

    require(AuthController.canCallSubAuthority(router, address(this)), "RouterAware: Not authorized");
    router = _router;
  }
}
