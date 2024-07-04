// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

struct StateSnapshot {
    uint256 agentBalanceWFIL;
    uint256 poolBalanceWFIL;
    uint256 agentBorrowed;
    uint256 agentPoolBorrowCount;
    uint256 accountEpochsPaid;
}

error Unauthorized();
error InvalidParams();
error InsufficientLiquidity();
error InsufficientCollateral();
error InvalidCredential();

uint256 constant WAD = 1e18;
// max FIL value - 2B atto
uint256 constant MAX_FIL = 2e27;
uint256 constant DUST = 10000;
uint256 constant MAX_UINT256 = type(uint256).max;
