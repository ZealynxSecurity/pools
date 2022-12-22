// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import "./BaseTest.sol";

contract PoolTemplateStakingTest is BaseTest {
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

  function testAsset() public {
    ERC20 asset = pool.getAsset();
    assertEq(asset.name(), "Wrapped Filecoin");
    assertEq(asset.symbol(), "WFIL");
    assertEq(asset.decimals(), 18);
  }

  function testPoolToken() public {
    ERC20 poolToken = ERC20(address(pool));
    assertEq(poolToken.name(), poolName);
    assertEq(poolToken.symbol(), poolSymbol);
    assertEq(poolToken.decimals(), 18);
  }

  function testSingleDepositWithdraw() public {
    uint256 investor1UnderlyingAmount = 1e18;

    vm.prank(investor1);
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    assertEq(wFIL.allowance(investor1, address(pool4626)), investor1UnderlyingAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    vm.prank(investor1);
    uint256 investor1ShareAmount = pool4626.deposit(investor1UnderlyingAmount, investor1);

    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount);
    assertEq(pool4626.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool4626.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool4626.totalAssets(), investor1UnderlyingAmount);


    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(pool20.balanceOf(investor1), investor1ShareAmount);
    assertEq(pool20.totalSupply(), investor1ShareAmount);

    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    pool4626.withdraw(investor1UnderlyingAmount, investor1, investor1);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor1)), 0);

    assertEq(pool4626.totalAssets(), 0);
    assertEq(pool20.balanceOf(investor1), 0);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal);
  }

  function testSingleMintRedeem() public {
    uint256 investor1ShareAmount = 1e18;

    vm.prank(investor1);
    wFIL.approve(address(pool), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    vm.prank(investor1);
    uint256 investor1UnderlyingAmount = pool4626.mint(investor1ShareAmount, investor1);

    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(investor1ShareAmount, investor1UnderlyingAmount);
    assertEq(pool4626.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool4626.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(pool4626.totalAssets(), investor1UnderlyingAmount);

    assertEq(pool20.totalSupply(), investor1ShareAmount);
    assertEq(pool20.balanceOf(investor1), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    pool4626.redeem(investor1ShareAmount, investor1, investor1);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor1)), 0);
    assertEq(pool4626.totalAssets(), 0);

    assertEq(pool20.balanceOf(investor1), 0);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal);
  }

  function testMultipleMintDepositRedeemWithdraw() public {
    // Scenario:
    // A = investor3, B = investor2
    //  ________________________________________________________
    // | Pool shares | A share | A assets | B share | B assets  |
    // |========================================================|
    // | 1. investor3 mints 2000 shares (costs 2000 tokens)     |
    // |--------------|---------|----------|---------|----------|
    // |         2000 |    2000 |     2000 |       0 |        0 |
    // |--------------|---------|----------|---------|----------|
    // | 2. investor2 deposits 4000 tokens (mints 4000 shares)  |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     2000 |    4000 |     4000 |
    // |--------------|---------|----------|---------|----------|
    // | 3. Pool mutates by +3000 tokens...                     |
    // |    (simulated yield returned from strategy)...         |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     3000 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 4. investor3 deposits 2000 wFIL (mints 1333 shares)    |
    // |--------------|---------|----------|---------|----------|
    // |         7333 |    3333 |     4999 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 5. investor2 mints 2000 shares (costs 3001 wFIL)       |
    // | NOTE: investor2's assets spent got rounded up          |
    // | NOTE: investor3's simpleInterestPool assets rounded up |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     5000 |    6000 |     9000 |
    // |--------------|---------|----------|---------|----------|
    // | 6. Vault mutates by +3000 tokens...                    |
    // |    (simulated yield returned from strategy)            |
    // |    NOTE: Vault holds 17001 tokens, but sum of          |
    // |          assetsOf() is 17000.                          |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     6071 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 7. investor3 redeems 1333 shares (2428 assets)         |
    // |--------------|---------|----------|---------|----------|
    // |         8000 |    2000 |     3643 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 8. investor2 withdraws 2928 assets (1608 shares)             |
    // |--------------|---------|----------|---------|----------|
    // |         6392 |    2000 |     3643 |    4392 |     8000 |
    // |--------------|---------|----------|---------|----------|
    // | 9. investor3 withdraws 3643 assets (2000 shares)           |
    // |    NOTE: investor2's assets have been rounded back up        |
    // |--------------|---------|----------|---------|----------|
    // |         4392 |       0 |        0 |    4392 |     8001 |
    // |--------------|---------|----------|---------|----------|
    // | 10. investor2 redeem 4392 shares (8001 tokens)               |
    // |--------------|---------|----------|---------|----------|
    // |            0 |       0 |        0 |       0 |        0 |
    // |______________|_________|__________|_________|__________|

    vm.deal(investor3, 1e18);
    vm.deal(investor2, 1e18);

    uint256 mutationUnderlyingAmount = 600;

    vm.startPrank(investor3);
    wFIL.deposit{value: 4000}();

    wFIL.approve(address(pool), 4000);
    vm.stopPrank();

    assertEq(wFIL.allowance(investor3, address(pool)), 4000);

    vm.startPrank(investor2);
    wFIL.deposit{value: 6201}();
    wFIL.approve(address(pool), 6201);
    vm.stopPrank();

    assertEq(wFIL.allowance(investor2, address(pool)), 6201);

    // 1. investor3 mints 2000 shares (costs 2000 tokens)
    vm.prank(investor3);
    uint256 investor3UnderlyingAmount = pool4626.mint(2000, investor3);
    uint256 investor3ShareAmount = pool4626.previewDeposit(investor3UnderlyingAmount);

    // Expect to have received the requested mint amount.
    assertEq(investor3ShareAmount, 2000);
    assertEq(pool20.balanceOf(investor3), investor3ShareAmount);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), investor3UnderlyingAmount);
    assertEq(pool4626.convertToShares(investor3UnderlyingAmount), pool20.balanceOf(investor3));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor3UnderlyingAmount, 2000);

    // Sanity check.
    assertEq(pool20.totalSupply(), investor3ShareAmount);
    assertEq(pool4626.totalAssets(), investor3UnderlyingAmount);

    // 2. investor2 deposits 4000 tokens (mints 4000 shares)
    vm.prank(investor2);
    uint256 investor2ShareAmount = pool4626.deposit(4000, investor2);
    uint256 investor2UnderlyingAmount = pool4626.previewWithdraw(investor2ShareAmount);

    // Expect to have received the requested wFIL amount.
    assertEq(investor2UnderlyingAmount, 4000);
    assertEq(pool20.balanceOf(investor2), investor2ShareAmount);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), investor2UnderlyingAmount);
    assertEq(pool4626.convertToShares(investor2UnderlyingAmount), pool20.balanceOf(investor2));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor2ShareAmount, investor2UnderlyingAmount);

    // Sanity check.
    uint256 preMutationShareBal = investor3ShareAmount + investor2ShareAmount;
    uint256 preMutationBal = investor3UnderlyingAmount + investor2UnderlyingAmount;
    assertEq(pool20.totalSupply(), preMutationShareBal);
    assertEq(pool4626.totalAssets(), preMutationBal);
    assertEq(pool20.totalSupply(), 6000);
    assertEq(pool4626.totalAssets(), 6000);

    // 3. Pool mutates by +600 tokens...                    |
    //    (simulated yield returned from strategy)...
    // The Pool now contains more tokens than deposited which causes the exchange rate to change.
    // investor3 share is 33.33% of the Pool, investor 2 66.66% of the Pool.
    // investor3's share count stays the same but the wFIL amount changes from 2000 to 3000.
    // investor 2's share count stays the same but the wFIL amount changes from 4000 to 6000.
    vm.prank(investor1);
    wFIL.transfer(address(pool), 600);

    uint256 preMutationTotalAssets =  preMutationBal + mutationUnderlyingAmount;
    assertEq(pool20.totalSupply(), preMutationShareBal);
    assertEq(pool4626.totalAssets(), preMutationTotalAssets);
    assertEq(pool20.balanceOf(investor3), investor3ShareAmount);
    assertEq(
        pool4626.convertToAssets(pool20.balanceOf(investor3)),
        investor3UnderlyingAmount + (mutationUnderlyingAmount / 3) * 1
    );
    assertEq(pool20.balanceOf(investor2), investor2ShareAmount);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), investor2UnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

    // 4. investor3 deposits 2000 tokens (mints 1395 shares)
    vm.prank(investor3);
    pool4626.deposit(2000, investor3);
    uint256 newAssetsAdded = 2000 + preMutationTotalAssets;
    uint256 step4TotalSupply = preMutationShareBal + 1818;
    assertEq(pool4626.totalAssets(), newAssetsAdded, "Borrowing should mutate the total assets of the pool");
    assertEq(pool20.totalSupply(), step4TotalSupply, "Borrowing should mutate the total assets of the pool");
    assertEq(pool20.balanceOf(investor3), 3818);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 4199);
    assertEq(pool20.balanceOf(investor2), 4000);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 4400);

    // 5. investor 2 mints 2000 shares (costs 3001 assets)
    // NOTE: investor 2's assets spent got rounded up
    // NOTE: investor1's simpleInterestPool assets got rounded up
    vm.prank(investor2);
    pool4626.mint(2000, investor2);
    assertEq(pool20.totalSupply(), step4TotalSupply + 2000);
    assertEq(pool20.balanceOf(investor3), 3818);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 4200);
    assertEq(pool20.balanceOf(investor2), 6000);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 6600);

    // Sanity checks:
    // investor1 and investor2 should have spent all their tokens now
    assertEq(wFIL.balanceOf(investor3), 0);
    assertEq(wFIL.balanceOf(investor2), 0);
    // Assets in simpleInterestPool: 4k (investor3) + 6.2k (investor2) + .6k (yield) + 1 (round up)
    assertEq(pool4626.totalAssets(), 10801);

    // 6. Vault mutates by +600 assets
    // NOTE: Vault holds 11401 assets, but sum of assetsOf() is 11400.
    vm.prank(investor1);
    wFIL.transfer(address(pool), 600);
    assertEq(pool4626.totalAssets(), 11401);
    assertEq(pool20.totalSupply(), 9818);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 4433);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 6967);

    // 7. investor3 redeem 1818 shares (2111 assets)
    vm.prank(investor3);
    pool4626.redeem(1818, investor3, investor3);

    assertEq(wFIL.balanceOf(investor3), 2111);
    assertEq(pool20.totalSupply(), 8000);
    assertEq(pool4626.totalAssets(), 11401 - 2111);
    assertEq(pool20.balanceOf(investor3), 2000);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 2322);
    assertEq(pool20.balanceOf(investor2), 6000);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 6967);

    // 8. investor2 withdraws 1967 assets (1694 shares)

    vm.prank(investor2);
    pool4626.withdraw(1967, investor2, investor2);

    assertEq(wFIL.balanceOf(investor2), 1967);
    assertEq(pool20.totalSupply(), 6306);
    assertEq(pool4626.totalAssets(), 7323);
    assertEq(pool20.balanceOf(investor3), 2000);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 2322);
    assertEq(pool20.balanceOf(investor2), 4306);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 5000);

    // 9. investor3 withdraws 2322 assets (2000 shares)
    // NOTE: investor 2's assets have been rounded back up
    vm.prank(investor3);
    pool4626.withdraw(2322, investor3, investor3);

    assertEq(wFIL.balanceOf(investor3), 4433);
    assertEq(pool20.totalSupply(), 4306);
    assertEq(pool4626.totalAssets(), 5001);
    assertEq(pool20.balanceOf(investor3), 0);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 0);
    assertEq(pool20.balanceOf(investor2), 4306);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 5001);

    // 10. investor2 redeem 4306 shares (5001 tokens)
    vm.prank(investor2);
    pool4626.redeem(4306, investor2, investor2);
    assertEq(wFIL.balanceOf(investor2), 6968);
    assertEq(pool20.totalSupply(), 0);
    assertEq(pool4626.totalAssets(), 0);
    assertEq(pool20.balanceOf(investor3), 0);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor3)), 0);
    assertEq(pool20.balanceOf(investor2), 0);
    assertEq(pool4626.convertToAssets(pool20.balanceOf(investor2)), 0);

    // Sanity check
    assertEq(wFIL.balanceOf(address(pool)), 0);
  }

  function testFailDepositWithNotEnoughApproval() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool4626), 0.5e18);
        assertEq(wFIL.allowance(address(this), address(pool)), 0.5e18);

        pool4626.deposit(1e18, address(this));
    }

    function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool4626), 0.5e18);

        pool4626.deposit(0.5e18, address(this));

        pool4626.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughShareAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool4626), 0.5e18);

        pool4626.deposit(0.5e18, address(this));

        pool4626.redeem(1e18, address(this), address(this));
    }

    function testFailWithdrawWithNoUnderlyingAmount() public {
        pool4626.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNoShareAmount() public {
        pool4626.redeem(1e18, address(this), address(this));
    }

    function testFailDepositWithNoApproval() public {
        pool4626.deposit(1e18, address(this));
    }

    function testFailMintWithNoApproval() public {
        pool4626.mint(1e18, address(this));
    }

    function testFailDepositZero() public {
        pool4626.deposit(0, address(this));
    }

    function testMintZero() public {
        pool4626.mint(0, address(this));

        assertEq(pool20.balanceOf(address(this)), 0);
        assertEq(pool4626.convertToAssets(pool20.balanceOf(address(this))), 0);
        assertEq(pool20.totalSupply(), 0);
        assertEq(pool4626.totalAssets(), 0);
    }

    function testFailRedeemZero() public {
        pool4626.redeem(0, address(this), address(this));
    }

    function testWithdrawZero() public {
        pool4626.withdraw(0, address(this), address(this));

        assertEq(pool20.balanceOf(address(this)), 0);
        assertEq(pool4626.convertToAssets(pool20.balanceOf(address(this))), 0);
        assertEq(pool20.totalSupply(), 0);
        assertEq(pool4626.totalAssets(), 0);
    }
}

contract PoolTemplateBorrowingTest is BaseTest {
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

  uint256 borrowAmount = 0.5e18;
  uint256 investor1UnderlyingAmount = 1e18;
  address investor1 = makeAddr("INVESTOR1");
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

  function testBorrow() public {
    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool4626.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();
    uint256 prevMinerBal = wFIL.balanceOf(address(agent));

    uint256 powerAmtStake = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);

    uint256 startEpoch = block.number;
    pool.borrow(borrowAmount, vc, powerAmtStake);
    uint256 postMinerBal = wFIL.balanceOf(address(agent));

    vm.stopPrank();

    assertEq(postMinerBal - prevMinerBal, borrowAmount);

    Account memory account = pool.getAccount(address(agent));
    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, startEpoch);
    assertEq(account.nextDueDate, startEpoch + pool.period());
    assertGt(account.pmtPerPeriod, 0);

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));
    assertEq(poolPowTokenBal, powerAmtStake);
    assertEq(agentPowTokenBal, vc.miner.qaPower - powerAmtStake);
    assertEq(poolPowTokenBal + agentPowTokenBal, vc.miner.qaPower);
  }
}
