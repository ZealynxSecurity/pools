// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.17;

// import {ERC20} from "shim/ERC20.sol";
// import {IAgent} from "src/Types/Interfaces/IAgent.sol";
// import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
// import {IERC20} from "src/Types/Interfaces/IERC20.sol";
// import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
// import {IRouter} from "src/Types/Interfaces/IRouter.sol";
// import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
// import "./BaseTest.sol";

// contract IntegrationTest is BaseTest {
//   using Credentials for VerifiableCredential;
//   IAgent agent;

//   IPoolFactory poolFactory;
//   IPowerToken powerToken;
//   IPool pool;
//   IERC20 pool20;
//   IERC20 iou;
//   IOffRamp ramp;

//   SignedCredential signedCred;

//   address investor1 = makeAddr("INVESTOR1");
//   address investor2 = makeAddr("INVESTOR2");
//   address investor3 = makeAddr("INVESTOR3");
//   address minerOwner = makeAddr("MINER_OWNER");
//   address poolOperator = makeAddr("POOL_OPERATOR");
//   address poolAdmin = makeAddr("POOL_FACTORY_ADMIN");

//   string poolName = "POOL_1";
//   string poolSymbol = "POOL1";

//   function setUp() public {
//     poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
//     powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
//     treasury = IRouter(router).getRoute(ROUTE_TREASURY);
//     pool = createPool(poolName, poolSymbol, poolOperator, 20e18);
//     pool20 = IERC20(address(pool.share()));
//     iou = IERC20(address(pool.iou()));
//     ramp = IOffRamp(address(pool.ramp()));

//     vm.deal(investor1, 10e18);
//     vm.prank(investor1);
//     wFIL.deposit{value: 10e18}();
//     require(wFIL.balanceOf(investor1) == 10e18);

//     (agent,) = configureAgent(minerOwner);

//     signedCred = issueGenericSC(address(agent));
//   }

// function testSingleDepositBorrowRepayWithdraw() public {
//     uint256 investor1OriginalWFILBal = wFIL.balanceOf(investor1);
//     uint256 borrowAmount = 0.5e18;
//     // deposit some funds for investor 1
//     uint256 investor1UnderlyingAmount = 1e18;
//     vm.startPrank(investor1);
//     wFIL.approve(address(pool), investor1UnderlyingAmount);
//     pool.deposit(investor1UnderlyingAmount, investor1);
//     vm.stopPrank();

//     // agent mints some power to borrow against
//     uint256 agentPowerAmount = 1e18;
//     vm.startPrank(minerOwner);
//     agent.mintPower(agentPowerAmount, signedCred);
//     agent.borrow(borrowAmount, pool.id(), issueGenericSC(address(agent)), agentPowerAmount);
//     vm.stopPrank();

//     uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
//     uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));

//     uint256 poolAssetBal = wFIL.balanceOf(address(pool));
//     uint256 agentAssetBal = wFIL.balanceOf(address(agent));

//     assertEq(poolPowTokenBal, agentPowerAmount, "pool should have power tokens");
//     assertEq(agentPowTokenBal, 0, "agent should not have power tokens");
//     assertEq(poolAssetBal, investor1UnderlyingAmount - borrowAmount, "pool has incorrect asset bal");
//     assertEq(agentAssetBal, borrowAmount, "agent has incorrect asset bal");

//     // agent repays the borrow amount
//     vm.startPrank(minerOwner);
//     agent.exit(pool.id(), borrowAmount, issueGenericSC(address(agent)));
//     vm.stopPrank();

//     poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
//     agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));

//     poolAssetBal = wFIL.balanceOf(address(pool));
//     agentAssetBal = wFIL.balanceOf(address(agent));

//     assertEq(poolPowTokenBal, 0, "pool should not have power tokens");
//     assertEq(agentPowTokenBal, agentPowerAmount, "agent should have its power back after exiting");
//     assertEq(poolAssetBal, investor1UnderlyingAmount, "pool has incorrect asset bal");
//     assertEq(agentAssetBal, 0, "agent should haven no assets");

//     vm.startPrank(investor1);
//     pool.withdraw(investor1UnderlyingAmount, investor1, investor1);
//     assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0);

//     assertEq(pool20.balanceOf(investor1), 0);

//     assertEq(iou.balanceOf(investor1), 0);
//     assertEq(iou.balanceOf(address(ramp)), investor1UnderlyingAmount);
//     assertEq(ramp.iouTokensStaked(investor1), investor1UnderlyingAmount);

//     pool.harvestToRamp();

//     assertEq(wFIL.balanceOf(address(ramp)), investor1UnderlyingAmount);

//     vm.roll(block.number + 200);
//     ramp.realize();
//     ramp.claim();



//     assertEq(pool.totalAssets(), 0);
//     assertEq(pool20.balanceOf(investor1), 0);
//     assertEq(wFIL.balanceOf(investor1), investor1OriginalWFILBal, "investor1 should have its assets back");
//   }
// }
