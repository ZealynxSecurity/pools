// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";


contract RouterAware is Ownable {
  address router;

  function setRouter(address _router) public onlyOwner {
    router = _router;
  }
}
