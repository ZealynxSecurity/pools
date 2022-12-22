// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import "./BaseTest.sol";

contract IntegrationTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC4626 pool4626;
  IERC20 pool20;

  VerifiableCredential vc;
  uint8 v;
  bytes32 r;
  bytes32 s;

  address investor1 = makeAddr("INVESTOR1");
  address investor2 = makeAddr("INVESTOR2");
  address investor3 = makeAddr("INVESTOR3");
  address minerOwner = makeAddr("MINER_OWNER");
  address poolOperator = makeAddr("POOL_OPERATOR");

  string poolName = "POOL_1";
  string poolSymbol = "POOL1";

  function setUp() public {
    poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
    powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    treasury = IRouter(router).getRoute(ROUTE_TREASURY);
    pool = poolFactory.createPool(
      poolName,
      poolSymbol,
      poolOperator,
      address(new BasicRateModule(20e18))
    );
    pool4626 = IERC4626(address(pool));
    pool20 = IERC20(address(pool));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    (vc, v, r, s) = issueGenericVC(address(agent));
  }

function testSingleDepositBorrowRepayWithdraw() public {
    uint256 investor1OriginalWFILBal = wFIL.balanceOf(investor1);
    uint256 borrowAmount = 0.5e18;
    // deposit some funds for investor 1
    uint256 investor1UnderlyingAmount = 1e18;
    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool4626.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    // agent mints some power to borrow against
    uint256 agentPowerAmount = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(agentPowerAmount, vc, v, r, s);
    // approve the pool to pull the agent's power tokens on call to deposit
    powerToken.approve(address(pool), agentPowerAmount);

    pool.borrow(borrowAmount, vc, agentPowerAmount);
    vm.stopPrank();

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));

    uint256 poolAssetBal = wFIL.balanceOf(address(pool));
    uint256 agentAssetBal = wFIL.balanceOf(address(agent));

    assertEq(poolPowTokenBal, agentPowerAmount, "pool should have power tokens");
    assertEq(agentPowTokenBal, 0, "agent should not have power tokens");
    assertEq(poolAssetBal, investor1UnderlyingAmount - borrowAmount, "pool has incorrect asset bal");
    assertEq(agentAssetBal, borrowAmount, "agent has incorrect asset bal");

    // agent repays the borrow amount
    vm.startPrank(address(agent));
    wFIL.approve(address(pool), borrowAmount);
    pool.exitPool(borrowAmount, vc);
    vm.stopPrank();

    poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));

    poolAssetBal = wFIL.balanceOf(address(pool));
    agentAssetBal = wFIL.balanceOf(address(agent));

    assertEq(poolPowTokenBal, 0, "pool should not have power tokens");
    assertEq(agentPowTokenBal, agentPowerAmount, "agent should have its power back after exiting");
    assertEq(poolAssetBal, investor1UnderlyingAmount, "pool has incorrect asset bal");
    assertEq(agentAssetBal, 0, "agent should haven no assets");

    vm.prank(investor1);
    pool4626.withdraw(investor1UnderlyingAmount, investor1, investor1);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor1)), 0);

    assertEq(pool4626.totalAssets(), 0);
    assertEq(pool20.balanceOf(investor1), 0);
    assertEq(wFIL.balanceOf(address(pool)), 0, "Pool should have no assets");
    assertEq(wFIL.balanceOf(investor1), investor1OriginalWFILBal, "investor1 should have its assets back");
  }
}
