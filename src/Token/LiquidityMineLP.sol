// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "fevmate/utils/FilAddress.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "src/Auth/Ownable.sol";

uint256 constant MIN_REWARD_PER_EPOCH = 1e10;

/**
 * @title LiquidityMine
 * @author GLIF
 * @notice Responsible for distributing GLIF token rewards to users who lock iFIL tokens in the contract
 */
contract LiquidityMineLP is Ownable {
    using FixedPointMathLib for uint256;
    using FilAddress for address;

    error InsufficientLockedTokens();
    error NoRewardsToHarvest();
    error InsufficientRewardTokenBalance();
    error RewardPerEpochTooSmall();

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

    /// @notice the token that gets paid out as a reward (GLIF)
    IERC20 public immutable rewardToken;
    /// @notice the token that is locked in the LM (iFIL)
    IERC20 public immutable lockToken;
    /// @notice the last block in which the LM accounting was updated
    uint256 public lastRewardBlock;
    /// @notice the number of rewardTokens issued per block, changeable by the owner
    uint256 public rewardPerEpoch;
    /// @notice the number of rewards accrued per each lock token deposited into this contract
    uint256 public accRewardsPerLockToken;
    /// @notice the number of rewards accrued in total
    /// @dev necessary to track this separately from accRewardsPerLockToken because it ignores changes in the per block reward ratio
    uint256 public accRewardsTotal;
    /// @notice the total amount of claimed rewards tokens that have been transferred out of this contract
    uint256 public rewardTokensClaimed;
    /// @notice the total funding amount of the contract
    uint256 public totalRewardCap;
    /// @notice userInfo tracks information about each user that deposits locked tokens
    mapping(address => UserInfo) private _userInfo;

    event Deposit(
        address indexed caller, address indexed beneficiary, uint256 lockTokenAmount, uint256 rewardsUnclaimed
    );
    event Withdraw(address indexed caller, address indexed receiver, uint256 amount, uint256 rewardsUnclaimed);
    event Harvest(address indexed caller, address indexed receiver, uint256 amount, uint256 rewardsUnclaimed);
    event LogUpdateAccounting(
        uint64 lastRewardBlock, uint256 lockTokenSupply, uint256 accRewardsPerLockToken, uint256 accRewardsTotal
    );

    constructor(IERC20 _rewardToken, IERC20 _lockToken, uint256 _rewardPerEpoch, address _owner) Ownable(_owner) {
        rewardToken = _rewardToken;
        lockToken = _lockToken;
        rewardPerEpoch = _rewardPerEpoch;
        lastRewardBlock = block.number;

        // configuration checks
        _checkRewardsPerEpoch(_rewardPerEpoch);
        require(address(rewardToken) != address(0), "LiquidityMine Constructor: rewardToken is 0");
        require(address(lockToken) != address(0), "LiquidityMine Constructor: lockToken is 0");
    }

    /// @notice userInfo returns information about each user that deposits locked tokens
    function userInfo(address user) external view returns (UserInfo memory) {
        return _userInfo[user.normalize()];
    }

    /// @notice fundedEpochsLeft returns the number of epochs left until the LM is over
    function fundedEpochsLeft() external view returns (uint256) {
        (, uint256 accRewardsTotal_,) = _computeAccRewards();
        return (totalRewardCap - accRewardsTotal_) / rewardPerEpoch;
    }

    /// @notice rewardsLeft returns the number of reward tokens that are left to issue in the LM
    function rewardsLeft() external view returns (uint256) {
        (, uint256 accRewardsTotal_,) = _computeAccRewards();
        return totalRewardCap - accRewardsTotal_;
    }

    /// @notice pendingRewards returns the amount of rewards that a user can harvest
    function pendingRewards(address user) external view returns (uint256) {
        (uint256 accRewardsPerLockToken_,,) = _computeAccRewards();
        UserInfo storage u = _userInfo[user.normalize()];
        return u.lockedTokens.mulWadDown(accRewardsPerLockToken_) + u.unclaimedRewards - u.rewardDebt;
    }

    /// @notice deposit allows a user to deposit lockTokens into the LM, using msg.sender as the beneficiary
    function deposit(uint256 amount) external {
        deposit(amount, msg.sender);
    }

    /// @notice deposit allows a user to deposit lockTokens into the LM, specifying a beneficiary other than the caller
    function deposit(uint256 amount, address beneficiary) public {
        updateAccounting();

        beneficiary = beneficiary.normalize();
        UserInfo storage user = _userInfo[beneficiary];

        // when we deposit, if there are locked tokens already, we need to calculate how many unclaimed rewards are eligible for claiming
        if (user.lockedTokens > 0) {
            // update beneficiary's unclaimed rewards
            user.unclaimedRewards =
                user.unclaimedRewards + user.lockedTokens.mulWadDown(accRewardsPerLockToken) - user.rewardDebt;
        }

        // update beneficiary's locked tokens
        user.lockedTokens = user.lockedTokens + amount;
        // reset the beneficiary's reward debt to account for the accrued rewards
        user.rewardDebt = accRewardsPerLockToken.mulWadDown(user.lockedTokens);
        // lockTokens get taken from msg.sender
        lockToken.transferFrom(msg.sender, address(this), amount);

        emit Deposit(msg.sender, beneficiary, amount, user.lockedTokens);
    }

    /// @notice withdraw allows a user to withdraw lockTokens from the LM, using the msg.sender as the receiver
    function withdraw(uint256 amount) external {
        updateAccounting();

        _withdraw(amount, _userInfo[msg.sender], msg.sender);
    }

    /// @notice withdraw allows a user to withdraw lockTokens from the LM, specifying a receiver other than the caller
    function withdraw(uint256 amount, address receiver) external {
        updateAccounting();

        _withdraw(amount, _userInfo[msg.sender], receiver.normalize());
    }

    /// @notice harvest allows a user to withdraw rewards from the LM, specifying a receiver other than the caller
    function harvest(uint256 amount, address receiver) external {
        updateAccounting();

        _harvest(amount, _userInfo[msg.sender], receiver.normalize());
    }

    /// @notice withdrawAndHarvest allows a user to withdraw lockTokens and harvest rewards in a single transaction
    function withdrawAndHarvest(uint256 amount, address receiver) external {
        updateAccounting();

        UserInfo storage user = _userInfo[msg.sender];
        receiver = receiver.normalize();

        _withdraw(amount, user, receiver);
        _harvest(amount, user, receiver);
    }

    /// @notice updateAccounting updates the accruedRewardsPerLockToken, accRewardsTotal, and lastRewardBlock, callable by anyone
    function updateAccounting() public {
        (uint256 _accRewardsPerLockToken, uint256 _accRewardsTotal, uint256 _lockTokenSupply) = _computeAccRewards();
        if (block.number > lastRewardBlock) {
            accRewardsPerLockToken = _accRewardsPerLockToken;
            accRewardsTotal = _accRewardsTotal;
            lastRewardBlock = block.number;
            emit LogUpdateAccounting(uint64(lastRewardBlock), _lockTokenSupply, accRewardsPerLockToken, accRewardsTotal);
        }
    }

    /// @notice loadRewards pulls reward tokens from the caller into this contract and updates the totalRewardCap
    /// @dev loadRewards triggers an accounting update as to prevent rewards from accruing in blocks where there are no rewards
    function loadRewards(uint256 amount) external {
        // first update the accounting such that the new rewards don't get included in historical accRewardsPerLockToken
        updateAccounting();
        // add the new reward tokens to our internal balance tracker
        totalRewardCap += amount;
        // pull the tokens into the contract
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice _computeAccRewards derives a new value for accRewardsPerLockToken based on the current block and lastRewardBlock
    function _computeAccRewards()
        internal
        view
        returns (uint256 newAccRewardsPerLockToken, uint256 newAccRewardsTotal, uint256 lockTokenSupply)
    {
        lockTokenSupply = lockToken.balanceOf(address(this));
        // if there are locked tokens staked, and we have more rewards left to distribute, then compute the new rewards
        if (block.number > lastRewardBlock && lockTokenSupply > 0 && accRewardsTotal < totalRewardCap) {
            // the reward that just became available to the contract is based on the current block and lastRewardBlock
            uint256 newRewards = rewardPerEpoch * (block.number - lastRewardBlock);
            // if this sets us over the cap, we need to adjust the new rewards to not exceed the cap
            if (accRewardsTotal + newRewards > totalRewardCap) {
                newRewards = totalRewardCap - accRewardsTotal;
            }
            return (
                accRewardsPerLockToken + newRewards.divWadDown(lockTokenSupply),
                newRewards + accRewardsTotal,
                lockTokenSupply
            );
        }

        return (accRewardsPerLockToken, accRewardsTotal, lockTokenSupply);
    }

    function _withdraw(uint256 amount, UserInfo storage user, address receiver) internal {
        if (user.lockedTokens == 0) revert InsufficientLockedTokens();

        if (amount > user.lockedTokens) amount = user.lockedTokens;

        // compute the total amount of tokens the user can claim
        uint256 pending = user.lockedTokens.mulWadDown(accRewardsPerLockToken) + user.unclaimedRewards - user.rewardDebt;

        user.lockedTokens = user.lockedTokens - amount;
        user.rewardDebt = user.lockedTokens.mulWadDown(accRewardsPerLockToken);
        user.unclaimedRewards = pending;

        lockToken.transfer(receiver, amount);

        emit Withdraw(msg.sender, receiver, amount, pending);
    }

    function _harvest(uint256 amount, UserInfo storage user, address receiver) internal {
        // totalRewardDebt is the total amount of rewards that the user is entitled to based on their locked tokens
        uint256 totalRewardDebt = user.lockedTokens.mulWadDown(accRewardsPerLockToken);
        // pending is the total amount of rewards that the user can claim
        uint256 pending = totalRewardDebt + user.unclaimedRewards - user.rewardDebt;

        if (pending == 0) revert NoRewardsToHarvest();
        // this should never happen, as we should always have enough rewards in the contract to pay the accrued amount
        if (rewardToken.balanceOf(address(this)) < pending) revert InsufficientRewardTokenBalance();

        // if the user tries to harvest more than they're owed, reset harvest amount to the total amount owed
        if (amount > pending) amount = pending;
        // update user's unclaimed rewards
        user.unclaimedRewards = pending - amount;
        // adjust rewardDebt to the total amount of rewards the user is entitled to now
        user.rewardDebt = totalRewardDebt;
        // add the amount to the total rewards claimed
        rewardTokensClaimed += amount;

        rewardToken.transfer(receiver, amount);

        emit Harvest(msg.sender, receiver, amount, user.unclaimedRewards);
    }

    /// @notice since max FIL is 2e27 atto, we need to ensure that the lockTokens in this contract can never exceed 1*10^18 * newRewardPerBlock, or we run into accounting issues
    /// to give ourselves some room, add another 0 to the max FIL value in case a FIP changes max value (2e28) and subtract 1e18 from it (1e10)
    /// note that rewardPerEpoch CAN be 0, which will mean no new rewards are issued
    function _checkRewardsPerEpoch(uint256 _rewardPerEpoch) internal pure {
        if (_rewardPerEpoch > 0 && _rewardPerEpoch < MIN_REWARD_PER_EPOCH) revert RewardPerEpochTooSmall();
    }

    /// @notice setRewardPerEpoch allows the owner to change the totalRewardCap to continue the LM further
    /// @param _rewardsPerEpoch the new number of reward tokens to issue per block
    /// @dev this function triggers an accounting update to avoid applying a new reward rate to epochs at the old rate
    function setRewardPerEpoch(uint256 _rewardsPerEpoch) external onlyOwner {
        _checkRewardsPerEpoch(_rewardsPerEpoch);

        updateAccounting();

        rewardPerEpoch = _rewardsPerEpoch;
    }
}
