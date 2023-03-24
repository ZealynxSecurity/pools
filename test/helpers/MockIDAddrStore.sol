// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

// this basically just stores a mapping of miners to use as IDs
contract MockIDAddrStore {
  mapping(uint64 => address) public ids;
  uint64 public count = 1;

  function addAddr(address addr) external returns (uint64 id) {
    id = count;
    ids[count] = addr;
    count++;
  }
}
