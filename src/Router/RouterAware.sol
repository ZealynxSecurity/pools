// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

abstract contract RouterAware {
  address public router;
  address public admin;

  function setRouter(address _router) public {
    // we avoid the access control check if the router is not set yet
    if (router == address(0)) {
      router = _router;
      admin = msg.sender;
      return;
    }

    require(msg.sender == admin, "RouterAware: Not authorized");
    router = _router;
  }
}
