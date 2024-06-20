// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "test/echidna/EchidnaSetup.sol";
import "src/Token/LiquidityMineLP.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {UserInfo} from "src/Types/Structs/UserInfo.sol";

contract EchidnaLiquidityMineLP is EchidnaSetup {
    using FixedPointMathLib for uint256;

    LiquidityMineLP internal lm;
    uint256 internal deployBlock;

    uint256 internal constant REWARD_PER_EPOCH = 1e18;
    uint256 internal constant TOTAL_REWARDS = 75_000_000e18;

    address internal constant SYS_ADMIN = address(0x50000);

    constructor() payable {
        deployBlock = block.number;
        lm = new LiquidityMineLP(IERC20(address(rewardToken)), IERC20(address(lockToken)), REWARD_PER_EPOCH, SYS_ADMIN);

        // Mint initial rewards to system admin
        rewardToken.mint(SYS_ADMIN, TOTAL_REWARDS);

        // SysAdmin should have initial total rewards balance
        assert(rewardToken.balanceOf(SYS_ADMIN) == TOTAL_REWARDS);
    }

    function prepareTokens(uint256 amount) internal {
        lockToken.mint(USER1, amount);
        hevm.prank(USER1);
        lockToken.approve(address(lm), amount);
    }

    function prepareDeposit(uint256 depositAmount) internal {
        prepareTokens(depositAmount);
        hevm.prank(USER1);
        lm.deposit(depositAmount, USER1);
    }

    function loadRewards(uint256 amount) internal {
        rewardToken.mint(address(this), amount);
        rewardToken.approve(address(lm), amount);
        lm.loadRewards(amount);
    }

    function advanceBlocks(uint256 blocks) internal {
        hevm.roll(block.number + blocks);
    }

    // ============================================
    // ==                DEPOSIT                 ==
    // ============================================

    function test_locked_tokens_increase(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 1e24) return;

        prepareTokens(amount);

        UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 initialLockedTokens = userInfo.lockedTokens;

        hevm.prank(USER1);
        try lm.deposit(amount, USER1) {
            // continue
        } catch {
            assert(false);
        }

        uint256 finalLockedTokens = lm.userInfo(USER1).lockedTokens;

        assert(finalLockedTokens == amount + initialLockedTokens);
    }

    function test_unclaimed_rewards_calculation(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 1e24) return;

        prepareTokens(amount);
        hevm.prank(USER1);
        lm.deposit(amount, USER1);

        UserInfo memory user = lm.userInfo(USER1);

        // Calculate expected unclaimed rewards
        uint256 previousUnclaimedRewards = user.unclaimedRewards;
        uint256 lockedTokens = user.lockedTokens;
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 rewardDebt = user.rewardDebt;

        uint256 newlyAccruedRewards = accRewardsPerLockToken.mulWadDown(lockedTokens);
        uint256 expectedUnclaimedRewards = previousUnclaimedRewards + newlyAccruedRewards - rewardDebt;

        assert(user.unclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_calculation(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 1e24) return;

        prepareTokens(amount);
        hevm.prank(USER1);
        lm.deposit(amount, USER1);

        UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 expectedRewardDebt = lm.accRewardsPerLockToken().mulWadDown(userInfo.lockedTokens);

        assert(userInfo.rewardDebt == expectedRewardDebt);
    }

    function test_deposit_transfer_successful(uint256 amount) public {
        if (amount == 0) return;
        if (amount > 1e24) return;

        prepareTokens(amount);

        uint256 initialContractBalance = lockToken.balanceOf(address(lm));
        uint256 initialUserBalance = lockToken.balanceOf(USER1);

        hevm.prank(USER1);
        lm.deposit(amount);

        lm.updateAccounting();

        uint256 finalContractBalance = lockToken.balanceOf(address(lm));
        uint256 finalUserBalance = lockToken.balanceOf(USER1);

        Debugger.log("amount", amount);
        Debugger.log("initialContractBalance", initialContractBalance);
        Debugger.log("finalContractBalance", finalContractBalance);
        Debugger.log("difference", finalContractBalance - initialContractBalance);
        assert(finalContractBalance == initialContractBalance + amount);
        Debugger.log("initialUserBalance", initialUserBalance);
        Debugger.log("finalUserBalance", finalUserBalance);
        Debugger.log("difference", initialUserBalance - finalUserBalance);
        assert(finalUserBalance == initialUserBalance - amount);
    }

    // ============================================
    // ==               WITHDRAW                 ==
    // ============================================

    function test_locked_tokens_decrease(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        UserInfo memory userInfoBefore = lm.userInfo(USER1);
        uint256 initialLockedTokens = userInfoBefore.lockedTokens;
        Debugger.log("initialLockedTokens", initialLockedTokens);

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        uint256 finalLockedTokens = initialLockedTokens - withdrawAmount;

        UserInfo memory userInfoAfter = lm.userInfo(USER1);
        uint256 currentLockedTokens = userInfoAfter.lockedTokens;

        Debugger.log("finalLockedTokens", finalLockedTokens);
        Debugger.log("currentLockedTokens", currentLockedTokens);
        Debugger.log("difference", currentLockedTokens - finalLockedTokens);
        assert(finalLockedTokens == currentLockedTokens);
    }

    function test_unclaimed_rewards_update(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        UserInfo memory userInfoBefore = lm.userInfo(USER1);
        uint256 previousUnclaimedRewards = userInfoBefore.unclaimedRewards;
        uint256 lockedTokens = userInfoBefore.lockedTokens;
        uint256 rewardDebt = userInfoBefore.rewardDebt;
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        UserInfo memory userInfoAfter = lm.userInfo(USER1);

        uint256 newlyAccruedRewards = lockedTokens.mulWadDown(accRewardsPerLockToken);
        uint256 expectedUnclaimedRewards = previousUnclaimedRewards + newlyAccruedRewards - rewardDebt;

        uint256 finalUnclaimedRewards = userInfoAfter.unclaimedRewards;

        assert(finalUnclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_update(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        UserInfo memory userInfoAfter = lm.userInfo(USER1);

        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 lockedTokensAfterWithdraw = userInfoAfter.lockedTokens;

        uint256 expectedRewardDebt = lockedTokensAfterWithdraw.mulWadDown(accRewardsPerLockToken);

        assert(userInfoAfter.rewardDebt == expectedRewardDebt);
    }

    function test_withdraw_transfer_successful(uint256 depositAmount, uint256 withdrawAmount) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (withdrawAmount > depositAmount) return;

        prepareDeposit(depositAmount);

        uint256 initialContractBalance = IERC20(address(lockToken)).balanceOf(address(lm));
        uint256 initialUserBalance = IERC20(address(lockToken)).balanceOf(USER1);

        hevm.prank(USER1);
        lm.withdraw(withdrawAmount);

        uint256 finalContractBalance = IERC20(address(lockToken)).balanceOf(address(lm));
        uint256 finalUserBalance = IERC20(address(lockToken)).balanceOf(USER1);

        uint256 actualWithdrawAmount = (withdrawAmount > depositAmount) ? depositAmount : withdrawAmount;

        Debugger.log("initialContractBalance", initialContractBalance - actualWithdrawAmount);
        Debugger.log("finalContractBalance", finalContractBalance);
        Debugger.log("difference", initialContractBalance - actualWithdrawAmount - finalContractBalance);
        assert(finalContractBalance == initialContractBalance - actualWithdrawAmount);
        assert(finalUserBalance == initialUserBalance + actualWithdrawAmount);
    }

    // ============================================
    // ==                HARVEST                 ==
    // ============================================

    //  @audit-issue fails due to precision loss
    //  Debug("currentUnclaimedRewards", 23945999999999999999994)
    //  Debug("expectedUnclaimedRewards", 23865999999999999999995)
    function test_harvest_rewards_update(uint256 depositAmount, uint256 harvestAmount, uint256 nextBlocks) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (harvestAmount > depositAmount) return;

        if (harvestAmount == 0) return;
        if (nextBlocks > 1000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);

        advanceBlocks(nextBlocks);

        lm.updateAccounting();

        UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialUnclaimedRewards = userInfo.unclaimedRewards;
        uint256 lockedTokens = userInfo.lockedTokens;
        uint256 rewardDebt = userInfo.rewardDebt;

        uint256 newlyAccruedRewards = accRewardsPerLockToken.mulWadDown(lockedTokens);
        uint256 pendingRewards = newlyAccruedRewards + initialUnclaimedRewards - rewardDebt;
        uint256 initialClaimedRewards = lm.rewardTokensClaimed();

        assert(pendingRewards == lm.pendingRewards(USER1));

        uint256 actualHarvestAmount = (harvestAmount > pendingRewards) ? pendingRewards : harvestAmount;

        hevm.prank(USER1);
        lm.harvest(actualHarvestAmount, USER1);

        lm.updateAccounting();

        uint256 currentUnclaimedRewards = lm.userInfo(USER1).unclaimedRewards;
        uint256 expectedUnclaimedRewards = pendingRewards - actualHarvestAmount;
        uint256 totalClaimedRewards = lm.rewardTokensClaimed();

        assert(totalClaimedRewards == initialClaimedRewards + actualHarvestAmount);
        Debugger.log("currentUnclaimedRewards", currentUnclaimedRewards);
        Debugger.log("expectedUnclaimedRewards", expectedUnclaimedRewards);
        assert(currentUnclaimedRewards == expectedUnclaimedRewards);
    }

    function test_reward_debt_after_harvest(uint256 depositAmount, uint256 harvestAmount, uint256 nextBlocks) public {
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (harvestAmount > depositAmount) return;

        if (harvestAmount == 0) return;
        if (nextBlocks == 0 || nextBlocks > 1000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);

        advanceBlocks(nextBlocks);
        lm.updateAccounting();

        UserInfo memory userInfo = lm.userInfo(USER1);
        uint256 accRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 lockedTokens = userInfo.lockedTokens;

        uint256 expectedRewardDebt = accRewardsPerLockToken.mulWadDown(lockedTokens);

        uint256 actualHarvestAmount =
            (harvestAmount > lm.pendingRewards(USER1)) ? lm.pendingRewards(USER1) : harvestAmount;

        hevm.prank(USER1);
        lm.harvest(actualHarvestAmount, USER1);

        lm.updateAccounting();

        uint256 finalRewardDebt = lm.userInfo(USER1).rewardDebt;

        assert(finalRewardDebt == expectedRewardDebt);
    }

    // ============================================
    // ==          WITHDRAW & HARVEST            ==
    // ============================================

    function test_withdraw_and_harvest_basic(uint256 depositAmount, uint256 withdrawAmount, uint256 nextBlocks)
        public
    {
        if (depositAmount == 0 || withdrawAmount == 0) return;
        if (depositAmount > 1e24 || withdrawAmount > depositAmount) return;
        if (nextBlocks == 0 || nextBlocks > 1000) return;

        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);

        advanceBlocks(nextBlocks);
        lm.updateAccounting();

        UserInfo memory userOneInfoBefore = lm.userInfo(USER1); //
        uint256 initialLockedTokens = userOneInfoBefore.lockedTokens;
        Debugger.log("initialLockedTokens", initialLockedTokens);

        uint256 actualHarvestAmount =
            (withdrawAmount > lm.pendingRewards(USER1)) ? lm.pendingRewards(USER1) : withdrawAmount;

        uint256 initialRewardTokenBalanceUserTwo = rewardToken.balanceOf(USER2);

        hevm.prank(USER1);
        lm.withdrawAndHarvest(withdrawAmount, USER2);

        lm.updateAccounting();

        uint256 finalRewardTokenBalanceUserTwo = rewardToken.balanceOf(USER2);

        UserInfo memory userOneInfoAfter = lm.userInfo(USER1);

        // Assertions
        assert(userOneInfoAfter.lockedTokens == userOneInfoBefore.lockedTokens - withdrawAmount);
        assert(finalRewardTokenBalanceUserTwo == initialRewardTokenBalanceUserTwo + actualHarvestAmount);
    }

    // ============================================
    // ==           _COMPUTE ACC REWARDS         ==
    // ============================================

    function test_multiple_deposits_accrual(uint256 depositAmount1, uint256 depositAmount2, uint256 blocks) public {
        if (depositAmount1 == 0 || depositAmount2 == 0 || blocks == 0) return;
        if (depositAmount1 > 1e24 || depositAmount2 > 1e24 || blocks > 1000) return;

        uint256 initialLockTokenSupply = lockToken.balanceOf(address(lm));
        Debugger.log("initialLockTokenSupply", initialLockTokenSupply);

        // First deposit
        prepareDeposit(depositAmount1);
        loadRewards(TOTAL_REWARDS);

        // Ensure initial state
        if (lm.accRewardsPerLockToken() != 0) return;
        if (lm.accRewardsTotal() != 0) return;

        // Advance blocks and accrue rewards for the first deposit
        advanceBlocks(blocks);
        lm.updateAccounting();

        // Capture accrued rewards per lock token after the first deposit
        uint256 firstAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 firstAccRewardsTotal = lm.accRewardsTotal();

        // Second deposit
        prepareTokens(depositAmount2);
        hevm.prank(USER1);
        lm.deposit(depositAmount2, USER1);

        // Advance blocks and accrue rewards after the second deposit
        advanceBlocks(blocks);
        lm.updateAccounting();

        uint256 secondAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 secondAccRewardsTotal = lm.accRewardsTotal();
        uint256 lockTokenSupply = lockToken.balanceOf(address(lm));
        uint256 rewardCap = lm.totalRewardCap();

        // Calculate expected values
        uint256 totalDepositAmount = depositAmount1 + depositAmount2;

        // Accumulated rewards for the second deposit period
        uint256 expectedSecondNewRewards = REWARD_PER_EPOCH * blocks;
        if (expectedSecondNewRewards + firstAccRewardsTotal > rewardCap) {
            expectedSecondNewRewards = rewardCap - firstAccRewardsTotal;
        }

        uint256 expectedSecondAccRewardsPerLockToken =
            expectedSecondNewRewards.divWadDown(lockToken.balanceOf(address(lm)));

        // Combined expected values
        uint256 expectedTotalAccRewardsPerLockToken = firstAccRewardsPerLockToken + expectedSecondAccRewardsPerLockToken;
        uint256 expectedTotalAccRewardsTotal = firstAccRewardsTotal + expectedSecondNewRewards;

        Debugger.log("accRewardsPerLockToken", secondAccRewardsPerLockToken);
        Debugger.log("expectedAccRewardsPerLockToken", expectedTotalAccRewardsPerLockToken);
        Debugger.log("difference", secondAccRewardsPerLockToken - expectedTotalAccRewardsPerLockToken);
        assert(secondAccRewardsPerLockToken == expectedTotalAccRewardsPerLockToken);

        Debugger.log("accRewardsTotal", secondAccRewardsTotal);
        Debugger.log("expectedAccRewardsTotal", expectedTotalAccRewardsTotal);
        assert(secondAccRewardsTotal == expectedTotalAccRewardsTotal);
        assert(lockTokenSupply == totalDepositAmount + initialLockTokenSupply);
    }

    function test_reward_cap_exceeded(uint256 depositAmount, uint256 blocks) public {
        // Validate input parameters
        if (depositAmount == 0 || depositAmount > 1e24) return;
        if (blocks == 0) return;

        uint256 excessRewards = TOTAL_REWARDS; // Use a high rewards value to exceed the cap

        // Initialize the deposit
        prepareDeposit(depositAmount);
        loadRewards(excessRewards);

        // Ensure initial state
        lm.updateAccounting();
        require(lm.accRewardsTotal() == 0, "Initial rewards total should be zero");

        // Advance blocks to accrue rewards
        advanceBlocks(blocks);
        lm.updateAccounting();

        // Capture initial state
        uint256 accRewardsTotalBefore = lm.accRewardsTotal();
        require(accRewardsTotalBefore <= excessRewards, "Initial rewards do not match");

        // Advance enough blocks to exceed reward cap
        advanceBlocks(blocks);
        lm.updateAccounting();

        // Check if the rewards have been capped
        uint256 accRewardsTotalAfter = lm.accRewardsTotal();
        uint256 totalRewardCap = lm.totalRewardCap();
        Debugger.log("accRewardsTotalAfter", accRewardsTotalAfter);
        Debugger.log("totalRewardCap", totalRewardCap);
        assert(accRewardsTotalAfter <= totalRewardCap);
    }

    // ============================================
    // ==             setRewardPerEpoch          ==
    // ============================================

    function test_set_reward_per_epoch(
        uint256 depositAmount,
        uint256 initialBlocks,
        uint256 newRewardPerEpoch,
        uint256 subsequentBlocks
    ) public {
        // Validate input parameters
        if (depositAmount == 0 || newRewardPerEpoch == 0) return;
        if (depositAmount > 1e24) return;
        if (initialBlocks == 0 || subsequentBlocks == 0) return;
        if (initialBlocks > 1000 || subsequentBlocks > 1000) return;
        if (block.number < lm.lastRewardBlock()) return;

        // Initial deposit and reward loading
        prepareDeposit(depositAmount);
        loadRewards(TOTAL_REWARDS);

        uint256 rewardCap = lm.totalRewardCap();

        // Advance blocks to accrue initial rewards
        advanceBlocks(initialBlocks);
        lm.updateAccounting();

        // Capture initial state
        uint256 initialAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 initialAccRewardsTotal = lm.accRewardsTotal();

        // Change reward rate
        hevm.prank(SYS_ADMIN);
        lm.setRewardPerEpoch(newRewardPerEpoch);

        // Advance blocks to accrue rewards with the new reward rate
        advanceBlocks(subsequentBlocks);
        lm.updateAccounting();

        // Calculate expected values
        uint256 newRewardsAccrued = newRewardPerEpoch * subsequentBlocks;

        if (newRewardsAccrued + initialAccRewardsTotal > rewardCap) {
            newRewardsAccrued = rewardCap - initialAccRewardsTotal;
        }

        uint256 totalAccRewards = initialAccRewardsTotal + newRewardsAccrued;
        uint256 expectedAccRewardsPerLockToken =
            initialAccRewardsPerLockToken + newRewardsAccrued.divWadDown(lockToken.balanceOf(address(lm)));

        // Capture final state
        uint256 finalAccRewardsPerLockToken = lm.accRewardsPerLockToken();
        uint256 finalAccRewardsTotal = lm.accRewardsTotal();

        assert(finalAccRewardsPerLockToken == expectedAccRewardsPerLockToken);
        assert(finalAccRewardsTotal == totalAccRewards);
    }
}
