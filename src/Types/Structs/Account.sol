// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

/// @dev an Account is a struct for storing information about an agent's borrowing activity within a specific pool
/// each pool has 1 account per agent
struct Account {
    // the epoch in which the agent first borrowed from the pool
    uint256 startEpoch;
    // the total amount of funds that the agent has borrowed from the pool
    uint256 principal;
    // a cursor that represents the agent's payment history within the pool
    uint256 epochsPaid;
    // set to true after an Account has been writtenOff
    bool defaulted;
}
