// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

/**
 * @notice Info of each LM user.
 * `lockedTokens` is the total amount of lockTokens locked by the User
 * `rewardDebt` tracks both:
 *   (1) rewards that the user is not entitled to because they were not locking tokens while rewards were accruing, and
 *   (2) rewards that the user has already claimed
 * `unclaimedRewards` is the amount of rewards that the user has not yet claimed
 */
struct UserInfo {
    uint256 lockedTokens;
    uint256 rewardDebt;
    uint256 unclaimedRewards;
}
