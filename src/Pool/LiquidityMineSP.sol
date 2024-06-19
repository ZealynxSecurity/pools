// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable} from "src/auth/Ownable.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";
import {IERC20} from "src/types/Interfaces/IERC20.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";

interface ERC20Burnable is IERC20 {
    function burn(address from, uint256 value) external;
}

contract LiquidityMineSP is ILiquidityMineSP, Ownable {
    using FixedPointMathLib for uint256;
    using FilAddress for address;

    /// @notice the router contract that is responsible for routing messages to the correct contracts
    address private immutable _router;
    /// @notice the token that gets paid out as a reward (GLIF)
    IERC20 public immutable rewardToken;
    /// @notice the address of the Infinity Pool
    address public pool;
    /// @notice the total funding amount of the contract
    uint256 public totalRewardCap;
    /// @notice the total amount of rewards that have been accumulated to Agents
    uint256 public rewardTokensAllocated;
    /// @notice the total amount of claimed rewards tokens that have been transferred out of this contract
    uint256 public rewardTokensClaimed;
    /// @notice the amount of rewards tokens that were forfeited due to default
    uint256 public rewardTokensForfeited;
    /// @notice the total amount of rewardTokens that are allocatd per FIL in fees paid
    uint256 public rewardPerFIL;
    /// @notice maps an agent ID to their reward info
    mapping(uint256 => AgentLMInfo) private _agentInfo;

    event TokensAllocated(uint256 indexed agent, uint256 amount);
    event TokensForfeited(uint256 indexed agent, uint256 amount);
    event Harvest(address indexed caller, address indexed receiver, uint256 amount, uint256 rewardsUnclaimed);

    modifier onlyPool() {
        if (pool != msg.sender) revert Unauthorized();
        _;
    }

    constructor(IERC20 rewardToken_, address owner_, address router_, uint256 rewardPerFil_) Ownable(owner_) {
        rewardToken = rewardToken_;
        rewardPerFIL = rewardPerFil_;
        _router = router_;

        pool = IRouter(_router).getRoute(ROUTE_INFINITY_POOL);
    }

    /// @notice returns the amount of rewards that an agent ID can claim
    function pendingRewards(uint256 agentId) public view returns (uint256) {
        return _agentInfo[agentId].unclaimedRewards;
    }

    /// @notice returns the amount of rewards that an agent address can claim (convenience function)
    function pendingRewards(address agent) external view returns (uint256) {
        return pendingRewards(IAgent(agent).id());
    }

    /// @notice returns the amount of rewards that the system has left to allocate to Agents
    function rewardsLeft() external view returns (uint256) {
        return totalRewardCap - rewardTokensAllocated;
    }

    /// @notice returns the agentInfo for a particular agent ID
    function agentLMInfo(uint256 agentId) public view returns (AgentLMInfo memory) {
        return _agentInfo[agentId];
    }

    /// @notice returns the agentInfo for a particular agent address (convenience function)
    function agentLMInfo(address agent) external view returns (AgentLMInfo memory) {
        return _agentInfo[IAgent(agent).id()];
    }

    /// @notice hook that is called when an Agent makes a payment
    function onPaymentMade(uint256 agentID, uint256 feePayment) external onlyPool {
        AgentLMInfo storage info = _agentInfo[agentID];
        // increase the fees paid by the Agent
        info.feesPaid += feePayment;
        // compute the amount of rewards to allocate to this agent
        uint256 rewards = feePayment.mulWadDown(rewardPerFIL);
        // if this amount of rewards would bring us over the total reward cap, reduce the rewards to reach the cap
        if (rewards + rewardTokensAllocated > totalRewardCap) {
            rewards = totalRewardCap - rewardTokensAllocated;
        }
        // update the amount of unclaimed rewards for this agent
        info.unclaimedRewards += rewards;
        // update the total amount of rewards allocated
        rewardTokensAllocated += rewards;

        emit TokensAllocated(agentID, rewards);
    }

    /// @notice onDefault forfeits the rewards of an Agent that has defaulted
    function onDefault(uint256 agentID) external onlyPool {
        AgentLMInfo storage info = _agentInfo[agentID];
        // increase the amount of forfeited rewards
        uint256 toForfeit = info.unclaimedRewards;
        // burn the forfeited rewards
        ERC20Burnable(address(rewardToken)).burn(address(this), toForfeit);
        // decrease the allocated amount of rewards and reward cap after burning
        rewardTokensAllocated -= toForfeit;
        totalRewardCap -= toForfeit;
        // set the unclaimed rewards to 0
        info.unclaimedRewards = 0;
        // update accounting so its easy to track how many rewards have been forfeited
        rewardTokensForfeited += toForfeit;
        // emit
        emit TokensForfeited(agentID, toForfeit);
    }

    /// @notice allows the owner of an Agent to harvest rewards, passing the agent's owner as the receiver
    function harvest(address agent, uint256 amount) external {
        harvest(agent, msg.sender, amount);
    }

    /// @notice allows the owner of an Agent to harvest rewards on behalf of a recipient
    function harvest(address agent, address receiver, uint256 amount) public {
        AgentLMInfo storage info = _agentInfo[IAgent(agent).id()];
        // only the Agent's owner can harvest rewards on behalf of an Agent
        if (msg.sender != IAuth(agent).owner()) revert Unauthorized();
        // if an Agent is in default, but the onDefault has yet to be called, the call should revert
        if (IAgent(agent).defaulted()) revert Unauthorized();
        if (info.unclaimedRewards == 0) revert InsufficientRewards();
        // if the requested amount is greater than the unclaimed rewards, reduce the amount to the unclaimed rewards
        if (amount > info.unclaimedRewards) amount = info.unclaimedRewards;
        // subtract the claimed rewards from the user's unclaimed rewards in storage
        info.unclaimedRewards -= amount;
        // add the claimed reawrds to the user's claimed rewards in storage
        info.claimedRewards += amount;
        // update the rewardTokensClaimed for the whole contract
        rewardTokensClaimed += amount;
        // transfer the reward tokens to the receiver
        rewardToken.transfer(receiver, amount);

        emit Harvest(msg.sender, receiver, amount, info.unclaimedRewards);
    }

    /// @notice allows the owner of this contract to set the rewards per FIL paid ratio
    function setRewardPerFIL(uint256 rewardPerFIL_) external onlyOwner {
        if (rewardPerFIL_ >= totalRewardCap - rewardTokensAllocated) revert InsufficientRewards();
        rewardPerFIL = rewardPerFIL_;
    }

    /// @notice allows the owner of this contract to set the pool address
    function setPool(address pool_) external onlyOwner {
        if (pool_ == address(0)) pool = IRouter(_router).getRoute(ROUTE_INFINITY_POOL);
        else pool = pool_;
    }

    /// @notice allows the owner of this contract to load more rewards into the contract, extending the liquidity mine
    function loadRewards(uint256 amount) external {
        // update the total reward cap in the contract
        totalRewardCap += amount;
        // pull the tokens into this contract from the sender
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }
}
