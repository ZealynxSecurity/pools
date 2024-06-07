// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable} from "src/auth/Ownable.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";
import {IAgentPoliceHook} from "src/Types/Interfaces/IAgentPoliceHook.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC20} from "src/types/Interfaces/IERC20.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";

bytes4 constant PAY_SELECTOR = bytes4(0x9ba7e551);

contract AgentPoliceHook is IAgentPoliceHook, Ownable {
    using FixedPointMathLib for uint256;
    using FilAddress for address;

    error InsufficientRewards();
    error PoolInactive();

    struct AgentLMInfo {
        uint256 feesPaid;
        uint256 claimedRewards;
        uint256 unclaimedRewards;
    }

    /// @notice the router contract that is responsible for routing messages to the correct contracts
    address private immutable _router;
    /// @notice the token that gets paid out as a reward (GLIF)
    IERC20 public immutable rewardToken;
    /// @notice the total funding amount of the contract
    uint256 public totalRewardCap;
    /// @notice the total amount of rewards that have been accumulated to Agents
    uint256 public rewardTokensAllocated;
    /// @notice the total amount of claimed rewards tokens that have been transferred out of this contract
    uint256 public rewardTokensClaimed;
    /// @notice the total amount of rewardTokens that are allocatd per FIL in fees paid
    uint256 public rewardPerFIL;
    /// @notice pay function signature represents the 4byte function selector of the "Pay" function
    bytes4 private _paySelector = PAY_SELECTOR;
    /// @notice maps an agent ID to their reward info
    mapping(uint256 => AgentLMInfo) private _agentInfo;

    event TokensAllocated(address indexed agent, uint256 amount);
    event Harvest(address indexed caller, address indexed receiver, uint256 amount, uint256 rewardsUnclaimed);

    constructor(IERC20 rewardToken_, address owner_, address router_, uint256 rewardPerFil_) Ownable(owner_) {
        rewardToken = rewardToken_;
        _router = router_;
        rewardPerFIL = rewardPerFil_;
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

    /// @notice hook that is called when an Agent uses a credential, only callable by the AgentPolice contract
    function onCredentialUsed(address agent, VerifiableCredential calldata vc) external {
        // only the agentPolice can invoke this hook
        if (address(GetRoute.agentPolice(_router)) != msg.sender) revert Unauthorized();
        // CAN REMOVE: redundant check to ensure the agentID matches the ID in the credential
        if (IAgent(agent).id() != vc.subject) revert Unauthorized();

        // as long as this action is a pay selector, add tokens to the Agent's reward pool
        if (vc.action == _paySelector) {
            AgentLMInfo storage info = _agentInfo[vc.subject];
            // increase the fees paid by the Agent
            info.feesPaid += vc.value;
            // compute the amount of rewards to allocate to this agent
            uint256 rewards = _computeInterestPaid(vc.subject, vc).mulWadDown(rewardPerFIL);
            // if this amount of rewards would bring us over the total reward cap, reduce the rewards to reach the cap
            if (rewards + rewardTokensAllocated > totalRewardCap) {
                rewards = totalRewardCap - rewardTokensAllocated;
            }
            // update the amount of unclaimed rewards for this agent
            info.unclaimedRewards += rewards;
            // update the total amount of rewards allocated
            rewardTokensAllocated += rewards;

            emit TokensAllocated(agent, rewards);
        }
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
    function setRewardPerFIL(uint256 rewardPerFil_) external onlyOwner {
        rewardPerFIL = rewardPerFil_;
    }

    /// @notice allows the owner of this contract to set the pay function signature
    /// @dev this should only be used if an Agent contract gets updated and the pay function signature changes
    function setPayMsgSig(bytes4 paySelector_) external onlyOwner {
        _paySelector = paySelector_;
    }

    /// @notice allows the owner of this contract to load more rewards into the contract, extending the liquidity mine
    function loadRewards(uint256 amount) external {
        // update the total reward cap in the contract
        totalRewardCap += amount;
        // pull the tokens into this contract from the sender
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    /// @dev _computeInterestPaid returns the amount of interest paid for a given pay credential
    function _computeInterestPaid(uint256 agentID, VerifiableCredential memory vc) internal view returns (uint256) {
        // load the account from storage, note that this account is loaded BEFORE the account's accounting is updated in storage, after the payment is applied
        // this strategy will not work if the account's accounting is updated before the account is loaded here, as the interest is already applied
        Account memory account = AccountHelpers.getAccount(_router, agentID, 0);
        // compute the number of epochs that are owed to get current
        uint256 epochsToPay = block.number - account.epochsPaid;
        // multiply the rate by the principal to get the per epoch interest rate
        // the interestPerEpoch has an extra WAD to maintain precision
        uint256 interestPerEpoch =
            account.principal.mulWadUp(IPool(IRouter(_router).getRoute(ROUTE_INFINITY_POOL)).getRate(vc));
        // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
        // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
        uint256 interestOwed = interestPerEpoch.mulWadUp(epochsToPay);

        // if the value supplied to the call is less than the interest owed, the entire payment is applied as interest
        if (vc.value < interestOwed) return vc.value;
        // otherwise, vc.value is larger than the interest owed, so the interest paid the interest owed
        return interestOwed;
    }
}
