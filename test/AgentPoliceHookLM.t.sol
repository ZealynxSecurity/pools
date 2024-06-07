// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {Agent} from "src/Agent/Agent.sol";
import {InfinityPool} from "src/Pool/InfinityPool.sol";
import {Router, GetRoute} from "src/Router/Router.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {AgentPoliceHook, PAY_SELECTOR} from "src/Agent/AgentPoliceHookLM.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IERC20} from "src/types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {VerifiableCredential, AgentData} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {ROUTE_AGENT_POLICE, ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";

interface MintBurnERC20 is IERC20 {
    function mint(address to, uint256 value) external;
    function burn(address from, uint256 value) external;
}

uint256 constant RATE_MULTIPLIER = 951293759512937595129375951293;
uint256 constant BASE_RATE = 18e16;

contract AgentPoliceHookLMTest is Test {
    using FixedPointMathLib for uint256;

    AgentPoliceHook public hook;
    Router public router;
    IERC20 public rewardToken;

    address public agentPolice = makeAddr("agent police");
    address public pool = makeAddr("pool");
    address public sysAdmin = makeAddr("system admin");
    address public agent = makeAddr("agent");
    uint256 public agentID = 1;

    uint256 public fakeRate = 1e18;
    uint256 public rewardsPerFIL = 1e18;
    uint256 public totalRewards = 100_000_000e18;

    function setUp() public {
        router = new Router(sysAdmin);
        rewardToken = IERC20(address(new MockERC20("GLIF", "GLF", 18)));
        vm.startPrank(sysAdmin);
        router.pushRoute(ROUTE_AGENT_POLICE, agentPolice);
        router.pushRoute(ROUTE_INFINITY_POOL, pool);
        vm.stopPrank();

        hook = new AgentPoliceHook(rewardToken, sysAdmin, address(router), rewardsPerFIL);

        // return a known rate for the pool - 1000 attofil per block
        vm.mockCall(pool, abi.encodeWithSelector(InfinityPool.getRate.selector), abi.encode(fakeRate));
        // return a mock agent ID for the agent
        vm.mockCall(agent, abi.encodeWithSelector(bytes4(keccak256("id()"))), abi.encode(agentID));
    }

    // this test ensures that the hook can accrue rewards on interest payments
    // the rate in this example is set to 1% per block
    function testFuzzAccrueRewardsOnInterestPaymentSimple(uint256 rollFwdBlocks) public {
        rollFwdBlocks = bound(rollFwdBlocks, 1, EPOCHS_IN_YEAR);
        _loadRewards(totalRewards);
        // here we just roll directly to the block number we want to test
        vm.roll(rollFwdBlocks);
        // account set so that it has already borrowed 100 FIL
        uint256 principal = 100e18;
        // first set up a mock agent account that owes interest in the pool
        Account memory account = Account(0, principal, 0, false);
        // mock the Account in the router
        vm.mockCall(address(router), abi.encodeWithSelector(router.getAccount.selector), abi.encode(account));

        // set payment amount to a very large number to ensure we always pay all the interest owed to receive max tokens
        uint256 payment = type(uint256).max;

        vm.startPrank(agentPolice);
        hook.onCredentialUsed(
            agent,
            VerifiableCredential(
                address(0),
                agentID,
                block.number,
                block.number + 100,
                payment,
                Agent.pay.selector,
                // minerID irrelevant for pay action
                0,
                abi.encode(_emptyAgentData())
            )
        );

        assertEq(hook.agentLMInfo(1).feesPaid, payment, "fees paid should be equal to payment");
        assertEq(hook.rewardTokensClaimed(), 0, "reward tokens not claimed");
        assertEq(hook.rewardTokensAllocated(), (rewardsPerFIL * block.number), "reward tokens allocate invalid");
    }

    function testPayMsgSig() public {
        assertEq(Agent.pay.selector, PAY_SELECTOR, "agent pay function signature invalid");
    }

    function testRate() public {
        assertEq(1e29, BASE_RATE.mulWadUp(RATE_MULTIPLIER), "rate invalid");
    }

    function testGetRoutes() public {
        assertEq(address(GetRoute.agentPolice(address(router))), agentPolice, "agent police route invalid");
        assertEq(IRouter(router).getRoute(ROUTE_INFINITY_POOL), pool, "pool route invalid");
    }

    function testMocks() public {
        AgentData memory ad = _emptyAgentData();
        ad.gcred = 100;
        VerifiableCredential memory vc = VerifiableCredential(
            address(0), 1, block.number, block.number + 100, 1, Agent.pay.selector, 0, abi.encode(ad)
        );
        uint256 rate = IPool(pool).getRate(vc);
        assertEq(rate, fakeRate, "rate invalid");

        assertEq(IAgent(agent).id(), agentID, "agent id invalid");
    }

    function _emptyAgentData() internal pure returns (AgentData memory) {
        return AgentData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function _loadRewards(uint256 totalRewardsToDistribute) internal {
        MintBurnERC20(address(rewardToken)).mint(address(this), totalRewardsToDistribute);
        rewardToken.approve(address(hook), totalRewardsToDistribute);

        uint256 preloadBal = rewardToken.balanceOf(address(hook));
        uint256 preloadRewardCap = hook.totalRewardCap();
        hook.loadRewards(totalRewardsToDistribute);
        uint256 postloadBal = rewardToken.balanceOf(address(hook));
        uint256 postloadRewardCap = hook.totalRewardCap();

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
