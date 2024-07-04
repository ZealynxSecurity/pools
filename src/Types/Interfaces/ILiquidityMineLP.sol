// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UserInfo} from "src/Types/Structs/UserInfo.sol";

interface ILiquidityMineLP {
    function rewardToken() external view returns (IERC20);

    function lockToken() external view returns (IERC20);

    function lastRewardBlock() external view returns (uint256);

    function rewardPerEpoch() external view returns (uint256);

    function accRewardsPerLockToken() external view returns (uint256);

    function accRewardsTotal() external view returns (uint256);

    function rewardTokensClaimed() external view returns (uint256);

    function totalRewardCap() external view returns (uint256);

    function userInfo(address user) external view returns (UserInfo memory);

    function fundedEpochsLeft() external view returns (uint256);

    function rewardsLeft() external view returns (uint256);

    function pendingRewards(address user) external view returns (uint256);

    function deposit(uint256 amount) external;

    function deposit(uint256 amount, address beneficiary) external;

    function withdraw(uint256 amount) external;

    function withdraw(uint256 amount, address receiver) external;

    function harvest(uint256 amount, address receiver) external;

    function withdrawAndHarvest(uint256 amount, address receiver) external;

    function updateAccounting() external;

    function loadRewards(uint256 amount) external;

    function setRewardPerEpoch(uint256 _rewardsPerEpoch) external;
}
