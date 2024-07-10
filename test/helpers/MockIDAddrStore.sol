// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;

// this address is where the ID Store gets deployed in echidna, so we etch it in forge
address constant MOCK_ID_STORE_ADDR = 0xd5F051401ca478B34C80D0B5A119e437Dc6D9df5;

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
