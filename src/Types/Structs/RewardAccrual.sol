// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/// @dev the RewardAccrual struct tracks LP and treasury rewards in the pool
/// see the AccrualMath library for the helper methods 
struct RewardAccrual {
    // the amount of rewards that have accrued in total
    uint256 accrued;
    // the total amount of rewards that have been paid out
    uint256 paid;
    // the amount of rewards lost due to a liquidation 
    uint256 lost;
}
