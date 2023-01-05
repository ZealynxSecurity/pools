// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// this struct is mainly used to cut down on the number of local vars in the functions
struct Window {
    uint256 start;
    uint256 deadline;
    uint256 length;
}
