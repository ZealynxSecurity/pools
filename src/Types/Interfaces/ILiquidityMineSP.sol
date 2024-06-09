// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IERC20} from "src/types/Interfaces/IERC20.sol";

interface ILiquidityMineSP {
    error InsufficientRewards();
    error PoolInactive();

    struct AgentLMInfo {
        uint256 feesPaid;
        uint256 claimedRewards;
        uint256 unclaimedRewards;
    }

    function rewardToken() external view returns (IERC20);

    function pool() external view returns (address);

    function totalRewardCap() external view returns (uint256);

    function rewardTokensAllocated() external view returns (uint256);

    function rewardTokensClaimed() external view returns (uint256);

    function rewardTokensForfeited() external view returns (uint256);

    function rewardPerFIL() external view returns (uint256);

    function pendingRewards(uint256 agentId) external view returns (uint256);

    function pendingRewards(address agent) external view returns (uint256);

    function rewardsLeft() external view returns (uint256);

    function agentLMInfo(uint256 agentId) external view returns (AgentLMInfo memory);

    function agentLMInfo(address agent) external view returns (AgentLMInfo memory);

    function onPaymentMade(uint256 agentID, uint256 feePayment) external;

    function onDefault(uint256 agentID) external;

    function harvest(address agent, uint256 amount) external;

    function harvest(address agent, address receiver, uint256 amount) external;

    function setRewardPerFIL(uint256 rewardPerFil_) external;

    function setPool(address pool_) external;

    function loadRewards(uint256 amount) external;
}
