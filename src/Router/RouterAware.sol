// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";


contract RouterAware {
  address router;

  function setRouter(address _router) public {
    router = _router;
  }
}
