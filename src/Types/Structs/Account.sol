// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/// @dev an Account is a struct for storing information about an agent's borrowing activity within a specific pool
/// each pool has 1 account per agent
struct Account {
    // the epoch in which the agent first borrowed from the pool
    uint256 startEpoch;
    // a rate that is applied to the agent's borrowed amount on a per epoch basis
    /// @dev this is a fixed point number with 18 decimals, i.e. 20% = 0.2e18
    uint256 perEpochRate;
    // the total amount of power tokens staked by the account's agent in this pool
    uint256 powerTokensStaked;
    // the total amount of funds that the agent has borrowed from the pool
    uint256 totalBorrowed;
    // a cursor that represents the agent's payment history within the pool
    uint256 epochsPaid;
    // The last epoch that this account's rate was updated
    uint256 rateAdjEpoch;
}
