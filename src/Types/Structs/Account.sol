// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

struct Account {
    // the epoch in which the borrow function was called
    uint256 startEpoch;
    // set at time of borrow / repay / refinance
    uint256 pmtPerPeriod;
    // the total amount borrowed by the agent
    uint256 powerTokensStaked;
    uint256 totalBorrowed;
    uint256 epochsPaid;
}
