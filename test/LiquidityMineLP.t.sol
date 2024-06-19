// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {LiquidityMineLP, MIN_REWARD_PER_EPOCH} from "src/Token/LiquidityMineLP.sol";
import {Token} from "src/Token/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface MintERC20 is IERC20 {
    function mint(address to, uint256 value) external;
}

// constants
uint256 constant DUST = 1e11;
uint256 constant MAX_UINT256 = type(uint256).max;
uint256 constant MAX_FIL = 2_000_000_000e18;
uint256 constant EPOCHS_IN_DAY = 2880;
uint256 constant EPOCHS_IN_YEAR = EPOCHS_IN_DAY * 365;

contract LiquidityMineLPTest is Test {
    using FixedPointMathLib for uint256;

    LiquidityMineLP public lm;
    IERC20 public rewardToken;
    IERC20 public lockToken;
    uint256 public rewardPerEpoch;
    uint256 public totalRewards;
    uint256 public deployBlock;

    address investor = makeAddr("investor");
    address sysAdmin = makeAddr("sysAdmin");

    function setUp() public {
        rewardPerEpoch = 1_000_000e18;
        totalRewards = 100_000_000e18;
        rewardToken = IERC20(address(new Token("GLIF", "GLF", sysAdmin, address(this))));
        lockToken = IERC20(address(new Token("iFIL", "iFIL", sysAdmin, address(this))));

        deployBlock = block.number;
        lm = new LiquidityMineLP(rewardToken, lockToken, rewardPerEpoch, sysAdmin);
    }

    function test_Initialization() public {
        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");
        assertEq(lm.lastRewardBlock(), deployBlock, "lastRewardBlock should be the deploy block");
        assertEq(lm.rewardPerEpoch(), rewardPerEpoch, "rewardPerEpoch should be rewardPerEpoch set in constructor");
        assertEq(address(lm.rewardToken()), address(rewardToken), "rewardToken should be the MockERC20 address");
        assertEq(address(lm.lockToken()), address(lockToken), "lockToken should be the MockERC20 address");
    }

    function test_LoadRewards() public {
        // _loadRewards contains test assertions
        _loadRewards(totalRewards);
    }

    function testFuzz_RewardsLeft(uint256 forwardBlocks) public {
        vm.assume(forwardBlocks < EPOCHS_IN_YEAR * 100);

        forwardBlocks = 52;

        _loadRewards(totalRewards);
        _depositLockTokens(investor, 1e18);

        uint256 rewardsLeftToIssue = lm.rewardsLeft();
        assertEq(rewardsLeftToIssue, totalRewards, "rewardsLeft should be the total rewards to distribute");
        vm.roll(block.number + forwardBlocks);

        uint256 rewardsLeftAfterRoll = lm.rewardsLeft();
        uint256 expected = 0;
        if ((rewardPerEpoch * forwardBlocks) < totalRewards) {
            expected = totalRewards - (rewardPerEpoch * forwardBlocks);
        }
        assertEq(rewardsLeftAfterRoll, expected, "rewardsLeft should be totalRewards - forwardBlocks * rewardPerEpoch");
    }

    function test_FundedEpochsLeft() public {
        _loadRewards(totalRewards);

        // here we know the values so we can assert them explicitly
        assertEq(lm.fundedEpochsLeft(), 100, "fundedEpochsLeft should be 100");
    }

    function testFuzz_FundedEpochsLeft(uint256 forwardBlocks) public {
        vm.assume(forwardBlocks < EPOCHS_IN_YEAR * 100);

        _loadRewards(totalRewards);
        _depositLockTokens(investor, 1e18);

        uint256 epochsLeft = lm.fundedEpochsLeft();
        assertEq(
            epochsLeft,
            (totalRewards / rewardPerEpoch),
            "epochsLeft should be the total rewards divided by rewardPerEpoch"
        );

        vm.roll(block.number + forwardBlocks);
        uint256 epochsLeftAfterRoll = lm.fundedEpochsLeft();
        uint256 expected = 0;
        if ((totalRewards / rewardPerEpoch) > forwardBlocks) {
            expected = (totalRewards / rewardPerEpoch) - forwardBlocks;
        }
        assertEq(
            epochsLeftAfterRoll, expected, "epochsLeft should be totalRewards divided by rewardPerEpoch - forwardBlocks"
        );
    }

    // this test creates 1 user
    // user 1 deposits for the full duration
    // the end result should be 100% of rewards to user 1
    function test_SingleDepositWithdrawHarvestEarnsAllRewards() public {
        uint256 depositAmt = 1e18;

        assertEq(rewardToken.balanceOf(address(lm)), 0, "LM Contract should have 0 locked tokens");
        assertEq(lockToken.balanceOf(address(lm)), 0, "LM Contract should have 0 reward tokens");

        _loadRewards(totalRewards);
        _depositLockTokens(investor, depositAmt);

        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "LM Contract should have totalRewards");

        assertUserInfo(investor, depositAmt, 0, 0, "test_SingleDepositWithdrawHarvestEarnsAllRewards2");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        // since there is only 1 user that deposited for the duration of the LM, the user should receive 100% of rewards
        vm.roll(block.number + lm.fundedEpochsLeft());

        // we haven't updated pool accounting yet, so the accumulated rewards per lock token should still be 0 in storage
        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");
        assertEq(lm.pendingRewards(investor), totalRewards, "User should receive all rewards - 1");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");
        assertEq(rewardToken.balanceOf(investor), 0, "User should not have any reward tokens yet");
        assertEq(lockToken.balanceOf(investor), 0, "User should not have any locked tokens back yet");
        assertEq(lockToken.balanceOf(address(lm)), depositAmt, "LM should have deposit amt of locked tokens");
        assertUserInfo(investor, depositAmt, 0, 0, "test_SingleDepositWithdrawHarvestEarnsAllRewards3");

        // test update the pool and the results should not change
        lm.updateAccounting();

        // after updating the accounting, the accumulated rewards per share should be total rewards divided by the total locked tokens
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmt),
            "accRewardsPerLockToken should be total rewards divided by depositAmt"
        );
        assertEq(lm.pendingRewards(investor), totalRewards, "User should receive all rewards - 2");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");
        assertEq(rewardToken.balanceOf(investor), 0, "User should not have any reward tokens yet");
        assertEq(lockToken.balanceOf(investor), 0, "User should not have any locked tokens back yet");
        assertEq(lockToken.balanceOf(address(lm)), depositAmt, "LM should have deposit amt of locked tokens");
        assertUserInfo(investor, depositAmt, 0, 0, "test_SingleDepositWithdrawHarvestEarnsAllRewards4");

        // withdraw lockTokens
        vm.prank(investor);
        lm.withdraw(depositAmt);

        assertEq(lockToken.balanceOf(investor), depositAmt, "User should have locked tokens back");
        assertEq(lockToken.balanceOf(address(lm)), 0, "LM should have 0 deposit amt of locked tokens after withdrawal");
        // rewards have not been paid out yet
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be fully paid out yet");
        assertEq(rewardToken.balanceOf(investor), 0, "Reward token should not be fully paid out yet");
        // after withdrawing, the user should have pending rewards and no lockTokens. Rewards have not been paid out yet
        assertEq(
            lm.pendingRewards(investor),
            totalRewards,
            "User should still have pending rewards left after withdrawing lockTokens"
        );
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertUserInfo(investor, 0, 0, totalRewards, "test_SingleDepositWithdrawHarvestEarnsAllRewards5");

        // harvest all rewards
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);

        // after harvesting, the user should no longer have pending rewards.
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        // rewards have not been paid out yet
        assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out");
        assertEq(rewardToken.balanceOf(investor), totalRewards, "Reward token should be fully paid out");
        assertUserInfo(investor, 0, 0, 0, "test_SingleDepositWithdrawHarvestEarnsAllRewards6");
    }

    // this test makes two deposits in a row with known amounts and timing, to test the internal accounting of the LM
    function test_DepositTwoTimesClaimableTokens() public {
        uint256 depositAmt = 1e18;

        _loadRewards(totalRewards);
        MintERC20(address(lockToken)).mint(investor, 1e18 * 2);

        assertUserInfo(investor, 0, 0, 0, "test_DepositTwoTimes1");

        // deposit depositAmt lockTokens on behalf of investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt * 2);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("test_DepositTwoTimesClaimableTokens1");

        assertUserInfo(investor, depositAmt, 0, 0, "test_DepositTwoTimes2");

        // now we roll forward to half of the liquidity mine
        vm.roll(block.number + lm.fundedEpochsLeft() / 2);

        assertUserInfo(investor, depositAmt, 0, 0, "test_DepositTwoTimes3");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should have half of pending rewards");

        // make second deposit, and in the same block, check that we have the same pending rewards as before
        lm.deposit(depositAmt);

        assertEq(
            lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should have half of pending rewards 2"
        );

        assertRewardCapInvariant("test_DepositTwoTimesClaimableTokens2");

        // the internal structs should change after a deposit
        assertUserInfo(
            investor,
            depositAmt * 2,
            // after the deposit, the accRewardsPerLockToken increseases to half the total rewards (because we rolled forward half the lm duration and depositAmt is 1e18)
            // so the rewardDebt after the second deposit would include the second 1e18 deposit, doubling the reward debt from where it was previously
            totalRewards.divWadDown(2e18).mulWadDown(2e18),
            totalRewards.divWadDown(2e18),
            "test_DepositTwoTimes4"
        );

        // fast forward to the end of the LM with extra epochs
        vm.roll(block.number + lm.fundedEpochsLeft() + 1000);

        assertEq(lm.pendingRewards(investor), totalRewards, "User should have all rewards after LM ends");
        // test update the pool and the results should not change from last update
        assertUserInfo(
            investor,
            depositAmt * 2,
            totalRewards.divWadDown(2e18).mulWadDown(2e18),
            totalRewards.divWadDown(2e18),
            "test_DepositTwoTimes5"
        );

        assertRewardCapInvariant("test_DepositTwoTimesClaimableTokens3");

        // test update the pool and the results should not change
        lm.updateAccounting();
        // after updating the accounting, the internal structs should change
        assertUserInfo(
            investor,
            depositAmt * 2,
            totalRewards.divWadDown(2e18).mulWadDown(2e18),
            totalRewards.divWadDown(2e18),
            "test_DepositTwoTimes6"
        );

        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        // after updating the accounting, the accumulated rewards per share should be:
        // 1st half: 37.5e18 / 1e18 = 37.5e18
        // 2nd half: 37.5e18 / 2e18 = 18.75e18
        uint256 firstHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt);
        uint256 secondHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt.mulWadDown(2e18));
        assertEq(lm.accRewardsPerLockToken(), firstHalf + secondHalf, "accRewardsPerLockToken should be correct");
        assertEq(lm.pendingRewards(investor), totalRewards, "User should receive all rewards - 2");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");
        assertEq(rewardToken.balanceOf(investor), 0, "User should not have any reward tokens yet");
        assertRewardCapInvariant("test_DepositTwoTimesClaimableTokens4");
    }

    // this test creates 2 users
    // both users deposit for the duration of the LM
    // the end result should be 50% of rewards to user 1 and 50% to user 2
    function test_SplitRewardsEven() public {
        uint256 depositAmt = 1e18;
        address investor2 = makeAddr("investor2");

        _loadRewards(totalRewards);

        assertRewardCapInvariant("test_SplitRewardsEven1");

        MintERC20(address(lockToken)).mint(investor, 1e18);
        MintERC20(address(lockToken)).mint(investor2, 1e18);

        assertUserInfo(investor, 0, 0, 0, "test_SplitRewardsEven1");
        assertUserInfo(investor2, 0, 0, 0, "test_SplitRewardsEven2");

        // deposit depositAmt lockTokens on behalf of investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);
        vm.stopPrank();

        assertRewardCapInvariant("test_SplitRewardsEven2");

        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);
        vm.stopPrank();

        assertRewardCapInvariant("test_SplitRewardsEven3");

        // now we roll forward to the middle of the liquidity mine and check the pending rewards
        // since there is only 1 user that deposited for this portion of the LM, the user should receive 100% of rewards up to this point (50% of rewards)
        vm.roll(block.number + lm.fundedEpochsLeft());
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User1 should receive 50% of rewards");
        assertEq(lm.pendingRewards(investor2), totalRewards.divWadDown(2e18), "User2 should receive 50% of rewards");

        // test update the pool and the results should not change
        lm.updateAccounting();
        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        // after updating the accounting, the accumulated rewards per share should be total rewards divided by the total locked tokens
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmt * 2),
            "accRewardsPerLockToken should be total rewards divided by depositAmt"
        );
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User1 should receive 50% of rewards - 2");
        assertEq(lm.pendingRewards(investor2), totalRewards.divWadDown(2e18), "User2 should receive 50% of rewards - 2");

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");
        // notice how using the userInfo struct does not update the storage values
        assertUserInfo(investor, depositAmt, 0, 0, "test_SplitRewardsEven3");
        assertUserInfo(investor2, depositAmt, 0, 0, "test_SplitRewardsEven4");
        assertRewardCapInvariant("test_SplitRewardsEven4");
    }

    // this test creates 2 users
    // user 1 deposits for the first half, then withdraws
    // user 2 deposits for the second half
    // the end result should be 50% of rewards to user 1 and 50% to user 2
    function test_DualDepositSplitRewardsEvenStaggered() public {
        _loadRewards(totalRewards);

        assertRewardCapInvariant("test_DualDepositSplitRewardsEvenStaggered1");

        uint256 depositAmt = 1e18;
        address investor2 = makeAddr("investor2");
        uint256 totalFundedEpochs = lm.fundedEpochsLeft();

        MintERC20(address(lockToken)).mint(investor, 1e18);
        MintERC20(address(lockToken)).mint(investor2, 1e18);

        assertUserInfo(investor, 0, 0, 0, "test_DualDepositSplitRewardsEvenStaggered1");
        assertUserInfo(investor2, 0, 0, 0, "test_DualDepositSplitRewardsEvenStaggered2");

        // deposit depositAmt lockTokens on behalf of investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("test_DualDepositSplitRewardsEvenStaggered2");

        // now we roll forward to the middle of the liquidity mine and check the pending rewards
        // since there is only 1 user that deposited for this portion of the LM, the user should receive 100% of rewards up to this point (50% of rewards)
        vm.roll(block.number + (lm.fundedEpochsLeft() / 2));
        uint256 pending = lm.pendingRewards(investor);
        assertEq(pending, totalRewards.divWadDown(2e18), "User should receive 50% of rewards");
        assertEq(lockToken.balanceOf(investor), 0, "User should not have any locked tokens back yet");
        assertEq(rewardToken.balanceOf(investor), 0, "User should not have any reward tokens yet");

        // withdraw lockTokens (not rewards) from pool, which will trigger an updateAccounting call internally
        lm.withdraw(depositAmt);
        vm.stopPrank();

        assertRewardCapInvariant("test_DualDepositSplitRewardsEvenStaggered3");

        assertEq(
            lm.pendingRewards(investor), pending, "User did not withdraw rewards, should still have pending rewards"
        );
        assertEq(lockToken.balanceOf(investor), depositAmt, "User should have their locked tokens back");
        assertEq(rewardToken.balanceOf(investor), 0, "User should not have received rewards after withdrawing");
        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmt).divWadDown(2e18),
            "accRewardsPerLockToken should be total rewards divided by depositAmt, divided by 2 (50% of rewards)"
        );
        assertEq(lm.userInfo(investor).unclaimedRewards, pending, "User1 should have unclaimed pending rewards");
        assertEq(
            lm.fundedEpochsLeft(), totalFundedEpochs / 2, "fundedEpochsLeft should be half of the total funded epochs"
        );
        assertEq(lm.rewardsLeft(), totalRewards.divWadDown(2e18), "rewardsLeft should be 50% of total rewards");

        // now deposit the same amount for investor2 for the duration of the LM
        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("test_DualDepositSplitRewardsEvenStaggered4");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        // since there are is only 1 user that deposited for the duration of the LM, the users should split rewards 50/50
        vm.roll(block.number + lm.fundedEpochsLeft());
        pending = lm.pendingRewards(investor2);
        assertEq(pending, totalRewards.divWadDown(2e18), "User2 should receive 50% of rewards");

        // withdraw rewards from pool, which will trigger an updateAccounting call internally
        lm.withdraw(depositAmt);
        vm.stopPrank();

        assertRewardCapInvariant("test_DualDepositSplitRewardsEvenStaggered5");

        assertEq(
            lm.pendingRewards(investor2), pending, "User2 did not withdraw rewards, should still have pending rewards"
        );
        assertEq(lockToken.balanceOf(investor), depositAmt, "User2 should have their locked tokens back");
        assertEq(rewardToken.balanceOf(investor), 0, "User2 should have received 50% of rewards");
        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmt),
            "accRewardsPerLockToken should be total rewards divided by depositAmt (100% of rewards)"
        );
        assertEq(lm.userInfo(investor2).unclaimedRewards, pending, "User2 should have unclaimed pending rewards");

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(
            rewardToken.balanceOf(address(lm)),
            totalRewards,
            "Reward tokens are not paid out yet after lockToken withdrawals"
        );
    }

    // this test creates 2 predeposit users before the LM starts (at different epochs) and asserts that they earn the same rewards
    function test_PreDepositBeforeLMStarts() public {
        uint256 depositAmt = 1e18;
        address investor2 = makeAddr("investor2");

        _depositLockTokens(investor, depositAmt);

        // roll forward for a while before the LM starts
        vm.roll(block.number + 1000);

        // second depositor later should not get more rewards
        _depositLockTokens(investor2, depositAmt);

        assertEq(lm.accRewardsTotal(), 0, "accRewardsTotal should be 0");
        assertEq(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");

        assertLMInactive();

        // load tokens to trigger the LM start
        _loadRewards(totalRewards);

        assertEq(
            lm.fundedEpochsLeft(), totalRewards / rewardPerEpoch, "fundedEpochsLeft should be the full LM duration"
        );
        assertEq(lm.rewardsLeft(), lm.totalRewardCap(), "rewardsLeft should be the total reward cap");

        assertUserInfo(investor, depositAmt, 0, 0, "test_PreDepositBeforeLMStarts1");
        assertUserInfo(investor2, depositAmt, 0, 0, "test_PreDepositBeforeLMStarts2");

        assertEq(lm.accRewardsTotal(), 0, "accRewardsTotal should be 0");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        vm.roll(block.number + lm.fundedEpochsLeft() + 50);

        assertEq(lm.pendingRewards(investor), lm.pendingRewards(investor2), "Investors should receive the same rewards");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");

        lm.updateAccounting();

        assertEq(lm.accRewardsTotal(), totalRewards, "accRewardsTotal should be totalRewards");
        assertEq(lm.pendingRewards(investor), lm.pendingRewards(investor2), "Investors should receive the same rewards");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
    }

    // this test ensures that gaps in the LM are handled correctly
    // no rewards should accrue when the LM has no reward tokens
    function test_ExtendLMWithGap() public {
        uint256 depositAmt = 1e18;
        address investor2 = makeAddr("investor2");

        _depositLockTokens(investor, depositAmt);
        _depositLockTokens(investor2, depositAmt);

        // load tokens to trigger the LM start
        _loadRewards(totalRewards);

        // roll forward to the end of the LM
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.pendingRewards(investor), lm.pendingRewards(investor2), "Investors should receive the same rewards");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");

        // now one user harvests and stays in while the other completely exits
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);

        vm.prank(investor2);
        lm.withdrawAndHarvest(MAX_UINT256, investor2);

        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after harvesting");
        assertEq(lm.pendingRewards(investor2), 0, "User should have no pending rewards left after withdrawing");

        uint256 accruedRewardsPerToken = lm.accRewardsPerLockToken();
        uint256 accruedRewardsTotal = lm.accRewardsTotal();

        assertEq(accruedRewardsTotal, totalRewards, "accruedRewardsTotal should be totalRewards");

        // now we fast forward, and no rewards should be issued
        vm.roll(block.number + 1000);

        lm.updateAccounting();

        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after harvesting");
        assertEq(lm.pendingRewards(investor2), 0, "User should have no pending rewards left after withdrawing");

        assertEq(lm.accRewardsPerLockToken(), accruedRewardsPerToken, "accRewardsPerLockToken should not change");
        assertEq(lm.accRewardsTotal(), accruedRewardsTotal, "accRewardsTotal should not change");

        // now investor2 redeposits
        _depositLockTokens(investor2, depositAmt);

        // we reload the rewards to trigger the LM to start again
        _loadRewards(totalRewards);

        assertEq(lm.rewardsLeft(), totalRewards, "rewardsLeft should be totalRewards");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        vm.roll(block.number + lm.fundedEpochsLeft() + 50);

        // investors should have the same pending rewards
        assertEq(lm.pendingRewards(investor), lm.pendingRewards(investor2), "Investors should receive the same rewards");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");

        lm.updateAccounting();

        assertEq(lm.pendingRewards(investor), lm.pendingRewards(investor2), "Investors should receive the same rewards");
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");
    }

    // this test ensures that we can extend the LM
    function test_ExtendLM() public {
        uint256 depositAmt = 1e18;

        assertEq(rewardToken.balanceOf(address(lm)), 0, "LM Contract should have 0 locked tokens");

        _loadRewards(totalRewards);
        assertRewardCapInvariant("test_ExtendLM1");

        _depositLockTokens(investor, depositAmt);
        uint256 totalFundedEpochs = lm.fundedEpochsLeft();
        // total funded epochs should be the full duration
        assertEq(totalFundedEpochs, totalRewards / rewardPerEpoch, "fundedEpochsLeft should be the full LM duration");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        // since there is only 1 user that deposited for the duration of the LM, the user should receive 100% of rewards
        vm.roll(block.number + lm.fundedEpochsLeft());
        // harvest all rewards
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);
        vm.stopPrank();
        assertRewardCapInvariant("test_ExtendLM2");
        // after harvesting, the user should no longer have pending rewards.
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        // rewards have not been paid out yet
        assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out");
        assertEq(rewardToken.balanceOf(investor), totalRewards, "Investor should receive all rewards");
        assertUserInfo(investor, depositAmt, totalRewards, 0, "test_ExtendLM1");

        // extend the LM
        uint256 newRewards = totalRewards;
        _loadRewards(newRewards);

        assertRewardCapInvariant("test_ExtendLM3");
        assertEq(lm.totalRewardCap(), totalRewards * 2, "totalRewardCap should be totalRewards x2");
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), newRewards, "rewardsLeft should be newRewards");
        assertEq(lm.fundedEpochsLeft(), totalFundedEpochs, "fundedEpochsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), newRewards, "Liquidity mine should be refunded");

        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.pendingRewards(investor), newRewards, "User should have pending rewards after LM extension - 2");
        assertRewardCapInvariant("test_ExtendLM4");
        // harvest all rewards
        vm.prank(investor);
        lm.harvest(MAX_UINT256, investor);
        // after harvesting, the user should no longer have pending rewards.
        assertEq(lm.pendingRewards(investor), 0, "User should have no pending rewards left after withdrawing");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out - 2");
        assertEq(rewardToken.balanceOf(investor), totalRewards * 2, "Investor should receive all rewards - 2");
        assertRewardCapInvariant("test_ExtendLM5");
    }

    // this test creates 2 users
    // user 1 deposits for the full duration
    // user 2 deposits for the second half
    // the end result should be 75% of rewards to user 1 and 25% to user 2
    function test_DualDepositSplitRewardsUneven() public {
        uint256 depositAmt = 1e18;
        address investor2 = makeAddr("investor2");

        _loadRewards(totalRewards);

        MintERC20(address(lockToken)).mint(investor, 1e18);
        MintERC20(address(lockToken)).mint(investor2, 1e18);

        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven1");
        assertUserInfo(investor, 0, 0, 0, "test_DualDepositSplitRewardsUneven1");
        assertUserInfo(investor2, 0, 0, 0, "test_DualDepositSplitRewardsUneven2");

        // deposit depositAmt lockTokens on behalf of investor
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven2");

        // now we roll forward to the middle of the liquidity mine and check the pending rewards
        // since there is only 1 user that deposited for this portion of the LM, the user should receive 100% of rewards up to this point (50% of rewards)
        vm.roll(block.number + (lm.fundedEpochsLeft().divWadDown(2e18)));
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards");
        // no accounting update has been made yet, so no unclaimedRewards exist yet
        assertEq(lm.userInfo(investor).unclaimedRewards, 0, "User should not yet have unclaimed rewards");
        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven3");
        // test update the pool and the results should not change
        lm.updateAccounting();
        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        // after updating the accounting, the accumulated rewards per share should be total rewards divided by the total locked tokens
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmt).divWadDown(2e18),
            "accRewardsPerLockToken should be total rewards divided by depositAmt"
        );
        assertEq(lm.pendingRewards(investor), totalRewards.divWadDown(2e18), "User should receive 50% of rewards - 2");
        assertEq(
            lm.userInfo(investor).unclaimedRewards,
            0,
            "User should not have unclaimed rewards yet after pool accounting updates"
        );
        vm.stopPrank();

        // now deposit the same amount for investor2 for the duration of the LM
        vm.startPrank(investor2);
        lockToken.approve(address(lm), depositAmt);
        lm.deposit(depositAmt);

        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven4");

        // now we roll forward to the end of the liquidity mine and check the pending rewards
        // since there are 2 users that deposited for the duration of the LM, the users should receive 75% and 25% of rewards
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.pendingRewards(investor), totalRewards.mulWadUp(75e16), "User1 should receive 75% of rewards");
        assertEq(lm.pendingRewards(investor2), totalRewards.mulWadUp(25e16), "User2 should receive 25% of rewards");

        // test update the pool and the results should not change
        lm.updateAccounting();

        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven5");

        assertEq(lm.lastRewardBlock(), block.number, "lastRewardBlock should be the current block");
        assertEq(lm.pendingRewards(investor), totalRewards.mulWadUp(75e16), "User1 should receive 75% of rewards");
        assertEq(lm.pendingRewards(investor2), totalRewards.mulWadUp(25e16), "User2 should receive 25% of rewards");
        assertEq(
            lm.userInfo(investor).unclaimedRewards,
            0,
            "User1 should have 0% of rewards unclaimed after accounting updates"
        );
        assertEq(
            lm.userInfo(investor2).unclaimedRewards,
            0,
            "User2 should have 0% of rewards unclaimed after accounting updates"
        );
        // to re compute the accRewardsPerLockToken we have to consider the second 1e18 deposit
        uint256 accRewardsPerTokenFirstHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt);
        uint256 accRewardsPerTokenSecondHalf = totalRewards.divWadDown(2e18).divWadDown(depositAmt.mulWadDown(2e18));
        assertEq(
            lm.accRewardsPerLockToken(),
            accRewardsPerTokenFirstHalf + accRewardsPerTokenSecondHalf,
            "accRewardsPerLockToken should be total rewards divided by depositAmt"
        );
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), totalRewards, "Reward token should not be paid out yet");
        assertRewardCapInvariant("test_DualDepositSplitRewardsUneven6");
    }

    // this test ensures that no matter how many times a single user harvests, they will receive the same rewards over the duration of the LM
    function testFuzz_SingleUserMultipleHarvest(uint256 harvests, uint256 depositAmount) public {
        harvests = bound(harvests, 1, 100);
        depositAmount = bound(depositAmount, 1, 2_000_000_000e18);

        harvests = 2;
        depositAmount = 1;

        _loadRewards(totalRewards);

        MintERC20(address(lockToken)).mint(investor, depositAmount);
        vm.startPrank(investor);
        lockToken.approve(address(lm), depositAmount);
        lm.deposit(depositAmount);
        vm.stopPrank();

        uint256 epochsLeft = lm.fundedEpochsLeft();
        for (uint256 i = 0; i < harvests; i++) {
            // here we add extra epochs so we roll over the end of the LM to ensure everything works properly
            vm.roll(block.number + (epochsLeft / harvests) + 5);
            vm.prank(investor);
            lm.harvest(MAX_UINT256, investor);
        }

        // at this point, the accRewardsPerLockToken should be the total rewards
        assertEq(
            lm.accRewardsPerLockToken(),
            totalRewards.divWadDown(depositAmount),
            "accRewardsPerLockToken should be total rewards divided by depositAmount"
        );

        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertApproxEqAbs(rewardToken.balanceOf(investor), totalRewards, DUST, "User should receive all rewards");
        assertRewardCapInvariant("testFuzz_SingleUserMultipleHarvest");
    }

    // this test ensures that no matter how many users harvest, if they deposit the same amount at the same time, they will receive the same rewards
    function testFuzz_MultiUserDepositHarvest(uint256 accounts, uint256 depositAmount) public {
        accounts = bound(accounts, 1, 100);
        depositAmount = bound(depositAmount, 1, 2_000_000_000e18);

        _loadRewards(totalRewards);

        address[] memory users = new address[](accounts);

        // make deposits for each user
        for (uint256 i = 0; i < accounts; i++) {
            address user = makeAddr(concatStrings("", "user", vm.toString(i)));
            users[i] = user;
            _depositLockTokens(user, depositAmount);
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest1");

        // pick random users to harvest at 10 random epochs along the way
        uint256 fundedEpochsLeft = lm.fundedEpochsLeft();
        uint256 chunks = 10;
        if (accounts < chunks) {
            chunks = accounts;
        }
        for (uint256 i = 0; i < chunks; i++) {
            // here we add extra epochs so we roll over the end of the LM to ensure everything works properly
            vm.roll(block.number + (fundedEpochsLeft / chunks) + 5);
            address user = users[i];
            vm.prank(user);
            lm.harvest(MAX_UINT256, user);
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest2");

        // make sure the lm is over
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        // harvest rewards for each user to make sure all rewards are harvested
        for (uint256 i = 0; i < accounts; i++) {
            address user = users[i];
            vm.startPrank(user);
            uint256 pending = lm.pendingRewards(user);
            if (pending > 0) {
                lm.harvest(MAX_UINT256, user);
            } else {
                try lm.harvest(MAX_UINT256, user) {
                    assertTrue(false, "Should not be able to harvest 0 rewards");
                } catch {
                    // expected
                }
            }
            vm.stopPrank();
            assertApproxEqAbs(
                rewardToken.balanceOf(user),
                totalRewards.divWadDown(accounts * 1e18),
                DUST,
                "Received Rewards: User should receive proportionate rewards"
            );
        }

        assertRewardCapInvariant("testFuzz_MultiUserDepositHarvest3");
    }

    // this test ensures that rewards do not accrue if there would be a problem with rounding down on accRewardsPerLockToken
    // this situatin occurs when the lockTokenSupply > 1*10^18 * newRewards because divWadDown rounds to 0
    function testFuzz_NoRewardsAccrue(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, MAX_FIL);
        // load a small amount of rewards, such that it's 1 wei per block in reward distributions
        vm.prank(sysAdmin);
        lm.setRewardPerEpoch(MIN_REWARD_PER_EPOCH);
        _loadRewards(totalRewards);

        _depositLockTokens(investor, depositAmount);

        assertEq(lm.rewardsLeft(), totalRewards, "rewardsLeft should be totalRewards");

        // roll forward 1 block to accrue a small amount of reward token
        vm.roll(block.number + 1);

        lm.updateAccounting();

        assertGt(lm.accRewardsTotal(), 0, "accRewardsTotal should be greater than 0");
        assertGt(lm.accRewardsPerLockToken(), 0, "accRewardsPerLockToken should be 0");

        // roll to the end and all rewards should be distributed
        vm.roll(block.number + lm.fundedEpochsLeft());

        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertApproxEqAbs(lm.pendingRewards(investor), totalRewards, DUST, "Investor should receive all rewards");
    }

    function _loadRewards(uint256 totalRewardsToDistribute) internal {
        MintERC20(address(rewardToken)).mint(address(this), totalRewardsToDistribute);
        rewardToken.approve(address(lm), totalRewardsToDistribute);

        uint256 preloadBal = rewardToken.balanceOf(address(lm));
        uint256 preloadRewardCap = lm.totalRewardCap();
        lm.loadRewards(totalRewardsToDistribute);
        uint256 postloadBal = rewardToken.balanceOf(address(lm));
        uint256 postloadRewardCap = lm.totalRewardCap();

        assertEq(
            postloadBal,
            totalRewardsToDistribute + preloadBal,
            "Reward token balance should be the total rewards to distribute"
        );
        assertEq(
            postloadRewardCap,
            preloadRewardCap + totalRewardsToDistribute,
            "Reward token cap should be the total rewards to distribute"
        );
    }

    function _depositLockTokens(address user, uint256 amount) internal {
        MintERC20(address(lockToken)).mint(user, amount);
        uint256 preLockTokens = lm.userInfo(user).lockedTokens;
        vm.startPrank(user);
        lockToken.approve(address(lm), amount);
        lm.deposit(amount);
        vm.stopPrank();

        assertEq(
            lm.userInfo(user).lockedTokens, preLockTokens + amount, "User locked tokens should be the amount deposited"
        );
    }

    function assertUserInfo(
        address user,
        uint256 lockedTokens,
        uint256 rewardDebt,
        uint256 unclaimedRewards,
        string memory label
    ) internal {
        LiquidityMineLP.UserInfo memory u = lm.userInfo(user);
        assertEq(
            u.lockedTokens,
            lockedTokens,
            concatStrings(label, " User lockedTokens should be: ", vm.toString(lockedTokens))
        );
        assertEq(
            u.rewardDebt, rewardDebt, concatStrings(label, " User rewardDebt should be: ", vm.toString(rewardDebt))
        );
        assertEq(
            u.unclaimedRewards,
            unclaimedRewards,
            concatStrings(label, " User unclaimedRewards should be: ", vm.toString(unclaimedRewards))
        );
    }

    function assertLMInactive() internal {
        assertEq(lm.fundedEpochsLeft(), 0, "fundedEpochsLeft should be 0");
        assertEq(lm.rewardsLeft(), 0, "rewardsLeft should be 0");
        assertEq(rewardToken.balanceOf(address(lm)), 0, "Reward token should be fully paid out");
        assertEq(lm.totalRewardCap(), lm.accRewardsTotal(), "totalRewardCap should be 0");
    }

    // this invariant ensures the reward cap is always equal to the total rewards set in these tests
    function assertRewardCapInvariant(string memory label) internal {
        assertEq(
            lm.totalRewardCap(),
            lm.rewardTokensClaimed() + rewardToken.balanceOf(address(lm)),
            string(abi.encodePacked("Invariant assertRewardCapInvariant: ", label))
        );
    }

    function concatStrings(string memory label, string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(label, a, b));
    }
}
