// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {BytesLib} from "bytes-utils/BytesLib.sol";

error Unauthorized(
  address target,
  address caller,
  bytes4 funcSig,
  string reason
);

library Decode {
  function unauthorizedError(bytes memory b) internal pure returns (
    address target,
    address caller,
    bytes4 funcSig,
    string memory reason
  ) {
      (bytes4 selector, bytes memory params) = generic(b);
      require(
        selector == Unauthorized.selector,
        "decodeUnauthorized: selector mismatch"
      );

      (target, caller, funcSig, reason) = abi.decode(
        params,
        (address, address, bytes4, string)
      );
  }

  function generic(bytes memory b) internal pure returns (bytes4 selector, bytes memory params) {
    selector = bytes4(BytesLib.slice(b, 0, 4));
    params = BytesLib.slice(b, 4, b.length - 4);
  }
}


