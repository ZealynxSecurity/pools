// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IHevm.sol";
import "./Debugger.sol";

contract EchidnaConfig {
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Constant echidna addresses
    address internal constant USER1 = address(0x10000);
    address internal constant USER2 = address(0x20000);
    address internal constant USER3 = address(0x30000);
    uint256 internal constant INITIAL_BALANCE = 1_000_000e18;

    ////// MOCK FOR VM.LABEL //////
    mapping(address => string) private addressLabels;

    function setLabel(address addr, string memory name) internal {
        addressLabels[addr] = name;
    }

    function getLabel(address addr) internal view returns (string memory) {
        return addressLabels[addr];
    }
    //////////////////////////////

    ////// MOCK FOR makeAddr from Test //////
    // creates a labeled address and the corresponding private key
    function makeAddrAndKey(string memory name) internal returns (address addr, uint256 privateKey) {
        privateKey = uint256(keccak256(abi.encodePacked(name)));
        addr = hevm.addr(privateKey);
        setLabel(addr, name);
    }

    // creates a labeled address
    function makeAddr(string memory name) internal returns (address addr) {
        (addr,) = makeAddrAndKey(name);
    }
    ////////////////////////////////////////
}
