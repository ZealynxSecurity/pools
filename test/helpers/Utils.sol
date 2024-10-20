// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BytesLib} from "bytes-utils/BytesLib.sol";

function iToHex(bytes memory buffer) pure returns (string memory) {
    // Fixed buffer size for hexadecimal convertion
    bytes memory converted = new bytes(buffer.length * 2);

    bytes memory _base = "0123456789abcdef";

    for (uint256 i = 0; i < buffer.length; i++) {
        converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
        converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
    }

    return string(abi.encodePacked("0x", converted));
}

function errorSelector(bytes memory b) pure returns (bytes4 selector) {
    return bytes4(BytesLib.slice(b, 0, 4));
}
