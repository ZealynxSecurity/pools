// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MAX_FIL} from "./ProtocolTest.sol";
import {LiquidityMineSP} from "src/Token/LiquidityMineSP.sol";
import {Router, GetRoute} from "src/Router/Router.sol";
import {Token} from "src/Token/Token.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "src/types/Interfaces/IERC20.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";

interface MintERC20 is IERC20 {
    function mint(address to, uint256 value) external;
}

contract LiquidityMineSPTest is Test {
    using FixedPointMathLib for uint256;

    LiquidityMineSP public lm;
    Router public router;
    Token public rewardToken;

    address public pool = makeAddr("pool");
    address public sysAdmin = makeAddr("system admin");
    address public agentOwner = makeAddr("agent owner");
    address public agent = makeAddr("agent");
    uint256 public agentID = 1;

    // 1 reward token per 1 FIL
    uint256 public rewardsPerFIL = 1e18;
    uint256 public totalRewards = 100_000_000e18;

    function setUp() public {
        router = new Router(sysAdmin);
        rewardToken = new Token("GLIF", "GLF", sysAdmin, address(this));
        vm.startPrank(sysAdmin);
        router.pushRoute(ROUTE_INFINITY_POOL, pool);
        vm.stopPrank();

        lm = new LiquidityMineSP(IERC20(address(rewardToken)), sysAdmin, address(router), rewardsPerFIL);

        vm.mockCall(agent, abi.encodeWithSelector(bytes4(keccak256("id()"))), abi.encode(agentID));
        vm.mockCall(agent, abi.encodeWithSelector(IAuth.owner.selector), abi.encode(agentOwner));
        vm.mockCall(agent, abi.encodeWithSelector(bytes4(keccak256("defaulted()"))), abi.encode(false));
    }

    function testLoadRewards() public {
        _loadRewards(totalRewards);
    }

    function testLoadRewardsTwice() public {
        _loadRewards(totalRewards);
        _loadRewards(totalRewards);
    }

    function testFuzzOnPaymentMadeLessThanTotalRewards(uint256 paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, totalRewards);
        _loadRewards(totalRewards);

        _makePaymentAndAssert(paymentAmount);
    }

    function testFuzzOnPaymentMadeMoreThanTotalRewards(uint256 paymentAmount) public {
        paymentAmount = bound(paymentAmount, totalRewards + 1, MAX_FIL);
        _loadRewards(totalRewards);

        _makePaymentAndAssert(paymentAmount);
    }

    function testFuzzOnPaymentMadeIrrationalRewardPerFIL(uint256 rewardPerFIL, uint256 rewardCap, uint256 paymentAmount)
        public
    {
        rewardCap = bound(rewardCap, 2, totalRewards);
        rewardPerFIL = bound(rewardPerFIL, 1, rewardCap - 1);
        paymentAmount = bound(paymentAmount, 1, totalRewards);

        _loadRewards(rewardCap);
        vm.prank(sysAdmin);
        lm.setRewardPerFIL(rewardPerFIL);

        _makePaymentAndAssert(paymentAmount);
    }

    function testFuzzHarvest(uint256 paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, totalRewards);
        _loadRewards(totalRewards);

        _makePaymentAndAssert(paymentAmount);
        _harvestAndAssert(lm.pendingRewards(agentID));
    }

    function testFuzzHarvestTwice(uint256 paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, totalRewards);
        _loadRewards(totalRewards);

        _makePaymentAndAssert(paymentAmount);
        // harvest some rewards
        _harvestAndAssert(lm.pendingRewards(agentID) / 2);
        _harvestAndAssert(lm.pendingRewards(agentID));

        assertEq(lm.pendingRewards(agentID), 0, "pending rewards should be 0 after two harvests");
    }

    function testFuzzHarvestNoRewards() public {
        _loadRewards(totalRewards);
        _makePaymentAndAssert(1e18);
        _harvestAndAssert(0);
    }

    function testFuzzHarvestTooManyRewards() public {
        _loadRewards(totalRewards);
        _makePaymentAndAssert(1e18);
        _harvestAndAssert(lm.pendingRewards(agentID) * 2);
    }

    function testFuzzPayHarvestTwice(uint256 paymentAmount) public {
        paymentAmount = bound(paymentAmount, 1, totalRewards);
        _loadRewards(totalRewards);

        _makePaymentAndAssert(paymentAmount);
        _harvestAndAssert(lm.pendingRewards(agentID) / 2);
        _makePaymentAndAssert(paymentAmount);
        _harvestAndAssert(lm.pendingRewards(agentID));
    }

    function testOnDefault() public {
        _loadRewards(totalRewards);
        uint256 paymentAmount = 10e18;
        // generate some rewards to lose
        _makePaymentAndAssert(paymentAmount);

        uint256 unclaimedRewards = lm.agentLMInfo(agentID).unclaimedRewards;
        uint256 rewardsLeft = lm.rewardsLeft();
        uint256 rewardCap = lm.totalRewardCap();
        uint256 rewardsSupply = rewardToken.totalSupply();
        uint256 assets = rewardToken.balanceOf(address(lm));

        vm.startPrank(pool);
        lm.onDefault(agentID);

        assertEq(lm.rewardTokensForfeited(), unclaimedRewards, "forfeited rewards should be equal to unclaimed rewards");
        assertEq(paymentAmount, unclaimedRewards, "payment amount should be equal to unclaimed rewards");
        assertEq(lm.agentLMInfo(agentID).unclaimedRewards, 0, "unclaimed rewards should be 0 after a default");
        assertEq(lm.rewardsLeft(), rewardsLeft, "rewards left should not change after a default");
        assertEq(
            lm.totalRewardCap(),
            rewardCap - lm.rewardTokensForfeited(),
            "reward cap should decrease by forfeited rewards"
        );
        assertEq(
            rewardToken.totalSupply(),
            rewardsSupply - unclaimedRewards,
            "total supply should decrease by unclaimed rewards"
        );
        assertEq(
            rewardToken.balanceOf(address(lm)),
            assets - unclaimedRewards,
            "reward token balance should decrease by unclaimed rewards"
        );
    }

    function _harvestAndAssert(uint256 harvestAmount) internal {
        ILiquidityMineSP.AgentLMInfo memory beforeHarvestAgentInfo = lm.agentLMInfo(agentID);
        uint256 rewardsLeft = lm.rewardsLeft();
        uint256 rewardsClaimed = lm.rewardTokensClaimed();
        uint256 rewardsForfeited = lm.rewardTokensForfeited();
        uint256 rewardTokensAllocated = lm.rewardTokensAllocated();

        if (beforeHarvestAgentInfo.unclaimedRewards > 0) {
            vm.prank(agentOwner);
            lm.harvest(agent, harvestAmount);

            if (harvestAmount > beforeHarvestAgentInfo.unclaimedRewards) {
                harvestAmount = beforeHarvestAgentInfo.unclaimedRewards;
            }

            ILiquidityMineSP.AgentLMInfo memory afterHarvestAgentInfo = lm.agentLMInfo(agentID);
            assertEq(
                beforeHarvestAgentInfo.unclaimedRewards,
                afterHarvestAgentInfo.unclaimedRewards + harvestAmount,
                "unclaimed rewards should decrease by harvest amount"
            );
            assertEq(
                beforeHarvestAgentInfo.feesPaid,
                afterHarvestAgentInfo.feesPaid,
                "feesPaid should not change after harvest"
            );
            assertEq(
                beforeHarvestAgentInfo.claimedRewards + harvestAmount,
                afterHarvestAgentInfo.claimedRewards,
                "claimed rewards should increase by harvest amount"
            );
            assertEq(rewardsLeft, lm.rewardsLeft(), "rewards left should not change after harvest");
            assertEq(rewardsForfeited, lm.rewardTokensForfeited(), "reward tokens forfeited should not change");
            assertEq(rewardTokensAllocated, lm.rewardTokensAllocated(), "reward tokens allocated should not change");
            assertEq(
                rewardsClaimed + harvestAmount,
                lm.rewardTokensClaimed(),
                "reward tokens claimed should increase by harvest amount"
            );
        } else {
            vm.startPrank(agentOwner);
            vm.expectRevert(ILiquidityMineSP.InsufficientRewards.selector);
            lm.harvest(agent, harvestAmount);
        }
    }

    function _makePaymentAndAssert(uint256 paymentAmount) internal {
        ILiquidityMineSP.AgentLMInfo memory beforePayAgentInfo = lm.agentLMInfo(agentID);
        uint256 rewardsLeft = lm.rewardsLeft();
        uint256 rewardsClaimed = lm.rewardTokensClaimed();
        uint256 rewardsForfeited = lm.rewardTokensForfeited();
        uint256 rewardTokensAllocated = lm.rewardTokensAllocated();

        vm.prank(pool);
        lm.onPaymentMade(agentID, paymentAmount);

        ILiquidityMineSP.AgentLMInfo memory afterPayAgentInfo = lm.agentLMInfo(agentID);

        assertEq(
            afterPayAgentInfo.feesPaid,
            beforePayAgentInfo.feesPaid + paymentAmount,
            "fees paid should be equal to payment"
        );
        assertEq(
            afterPayAgentInfo.claimedRewards, beforePayAgentInfo.claimedRewards, "forfeited rewards should not change"
        );

        assertEq(rewardsClaimed, lm.rewardTokensClaimed(), "reward tokens claimed should not change");
        assertEq(rewardsForfeited, lm.rewardTokensForfeited(), "reward tokens forfeited should not change");

        uint256 expectedRewardTokensAllocated = paymentAmount.mulWadDown(lm.rewardPerFIL());
        if (expectedRewardTokensAllocated + rewardTokensAllocated > lm.totalRewardCap()) {
            expectedRewardTokensAllocated = lm.totalRewardCap() - rewardTokensAllocated;
        }

        assertEq(
            afterPayAgentInfo.unclaimedRewards,
            beforePayAgentInfo.unclaimedRewards + expectedRewardTokensAllocated,
            "unclaimed rewards should increase by payment amount * reward per FIL"
        );
        assertEq(
            lm.rewardsLeft(),
            rewardsLeft - expectedRewardTokensAllocated,
            "rewards left should be total rewards - payment"
        );
        assertEq(
            lm.rewardTokensAllocated(),
            rewardTokensAllocated + expectedRewardTokensAllocated,
            "reward tokens allocated should increase by payment amount * reward per FIL"
        );
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
}
