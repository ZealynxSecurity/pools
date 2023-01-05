// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IBroker} from "src/Types/Interfaces/IBroker.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Decode} from "src/Errors.sol";
import "./BaseTest.sol";

contract PoolTemplateStakingTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

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
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));
  }

  function testAsset() public {
    ERC20 asset = pool.getAsset();
    assertEq(asset.name(), "Wrapped Filecoin");
    assertEq(asset.symbol(), "WFIL");
    assertEq(asset.decimals(), 18);
  }

  function testPoolToken() public {
    // NOTE: any reason not to just use pool20 here?
    ERC20 poolToken = ERC20(address(pool.share()));
    assertEq(poolToken.name(), poolName);
    assertEq(poolToken.symbol(), poolSymbol);
    assertEq(poolToken.decimals(), 18);
  }

  function testSingleDepositWithdraw() public {
    uint256 investor1UnderlyingAmount = 1e18;

    vm.startPrank(investor1);
    wFIL.approve(address(pool.template()), investor1UnderlyingAmount);
    assertEq(wFIL.allowance(investor1, address(pool.template())), investor1UnderlyingAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    uint256 investor1ShareAmount = pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();
    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount);
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool.totalAssets(), investor1UnderlyingAmount);


    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(pool20.balanceOf(investor1), investor1ShareAmount);
    assertEq(pool20.totalSupply(), investor1ShareAmount);

    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    pool.withdraw(investor1UnderlyingAmount, investor1, investor1);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0);

    assertEq(pool.totalAssets(), 0);
    assertEq(pool20.balanceOf(investor1), 0);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal);
  }

  function testSingleMintRedeem() public {
    uint256 investor1ShareAmount = 1e18;

    vm.startPrank(investor1);
    wFIL.approve(address(pool.template()), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(pool.template())), investor1ShareAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    uint256 investor1UnderlyingAmount = pool.mint(investor1ShareAmount, investor1);
    vm.stopPrank();
    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(investor1ShareAmount, investor1UnderlyingAmount);
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount);
    assertEq(pool.totalAssets(), investor1UnderlyingAmount);

    assertEq(pool20.totalSupply(), investor1ShareAmount);
    assertEq(pool20.balanceOf(investor1), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);

    vm.prank(investor1);
    pool.redeem(investor1ShareAmount, investor1, investor1);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0);
    assertEq(pool.totalAssets(), 0);

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
    vm.startPrank(investor3);
    wFIL.approve(address(pool.template()), 2000);
    uint256 investor3UnderlyingAmount = pool.mint(2000, investor3);
    uint256 investor3ShareAmount = pool.previewDeposit(investor3UnderlyingAmount);
    vm.stopPrank();
    // Expect to have received the requested mint amount.
    assertEq(investor3ShareAmount, 2000);
    assertEq(pool20.balanceOf(investor3), investor3ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), investor3UnderlyingAmount);
    assertEq(pool.convertToShares(investor3UnderlyingAmount), pool20.balanceOf(investor3));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor3UnderlyingAmount, 2000);

    // Sanity check.
    assertEq(pool20.totalSupply(), investor3ShareAmount);
    assertEq(pool.totalAssets(), investor3UnderlyingAmount);

    // 2. investor2 deposits 4000 tokens (mints 4000 shares)
    vm.startPrank(investor2);
    wFIL.approve(address(pool.template()), 4000);
    uint256 investor2ShareAmount = pool.deposit(4000, investor2);
    vm.stopPrank();
    uint256 investor2UnderlyingAmount = pool.previewWithdraw(investor2ShareAmount);

    // Expect to have received the requested wFIL amount.
    assertEq(investor2UnderlyingAmount, 4000);
    assertEq(pool20.balanceOf(investor2), investor2ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor2UnderlyingAmount);
    assertEq(pool.convertToShares(investor2UnderlyingAmount), pool20.balanceOf(investor2));

    // Expect a 1:1 ratio before mutation.
    assertEq(investor2ShareAmount, investor2UnderlyingAmount);

    // Sanity check.
    uint256 preMutationShareBal = investor3ShareAmount + investor2ShareAmount;
    uint256 preMutationBal = investor3UnderlyingAmount + investor2UnderlyingAmount;
    assertEq(pool20.totalSupply(), preMutationShareBal);
    assertEq(pool.totalAssets(), preMutationBal);
    assertEq(pool20.totalSupply(), 6000);
    assertEq(pool.totalAssets(), 6000);

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
    assertEq(pool.totalAssets(), preMutationTotalAssets);
    assertEq(pool20.balanceOf(investor3), investor3ShareAmount);
    assertEq(
        pool.convertToAssets(pool20.balanceOf(investor3)),
        investor3UnderlyingAmount + (mutationUnderlyingAmount / 3) * 1
    );
    assertEq(pool20.balanceOf(investor2), investor2ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor2UnderlyingAmount + (mutationUnderlyingAmount / 3) * 2);

    // 4. investor3 deposits 2000 tokens (mints 1395 shares)
    vm.startPrank(investor3);
    wFIL.approve(address(pool.template()), 2000);
    pool.deposit(2000, investor3);
    vm.stopPrank();
    uint256 newAssetsAdded = 2000 + preMutationTotalAssets;
    uint256 step4TotalSupply = preMutationShareBal + 1818;
    assertEq(pool.totalAssets(), newAssetsAdded, "Borrowing should mutate the total assets of the pool");
    assertEq(pool20.totalSupply(), step4TotalSupply, "Borrowing should mutate the total assets of the pool");
    assertEq(pool20.balanceOf(investor3), 3818);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 4199);
    assertEq(pool20.balanceOf(investor2), 4000);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 4400);

    // 5. investor 2 mints 2000 shares (costs 3001 assets)
    // NOTE: investor 2's assets spent got rounded up
    // NOTE: investor1's simpleInterestPool assets got rounded up
    vm.startPrank(investor2);
    wFIL.approve(address(pool.template()), 3001);
    pool.mint(2000, investor2);
    vm.stopPrank();
    assertEq(pool20.totalSupply(), step4TotalSupply + 2000);
    assertEq(pool20.balanceOf(investor3), 3818);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 4200);
    assertEq(pool20.balanceOf(investor2), 6000);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 6600);

    // Sanity checks:
    // investor1 and investor2 should have spent all their tokens now
    assertEq(wFIL.balanceOf(investor3), 0);
    assertEq(wFIL.balanceOf(investor2), 0);
    // Assets in simpleInterestPool: 4k (investor3) + 6.2k (investor2) + .6k (yield) + 1 (round up)
    assertEq(pool.totalAssets(), 10801);

    // 6. Vault mutates by +600 assets
    // NOTE: Vault holds 11401 assets, but sum of assetsOf() is 11400.
    vm.prank(investor1);
    wFIL.transfer(address(pool), 600);
    assertEq(pool.totalAssets(), 11401);
    assertEq(pool20.totalSupply(), 9818);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 4433);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 6967);

    // 7. investor3 redeem 1818 shares (2111 assets)
    vm.prank(investor3);
    pool.redeem(1818, investor3, investor3);

    assertEq(wFIL.balanceOf(investor3), 2111);
    assertEq(pool20.totalSupply(), 8000);
    assertEq(pool.totalAssets(), 11401 - 2111);
    assertEq(pool20.balanceOf(investor3), 2000);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 2322);
    assertEq(pool20.balanceOf(investor2), 6000);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 6967);

    // 8. investor2 withdraws 1967 assets (1694 shares)

    vm.prank(investor2);
    pool.withdraw(1967, investor2, investor2);

    assertEq(wFIL.balanceOf(investor2), 1967);
    assertEq(pool20.totalSupply(), 6306);
    assertEq(pool.totalAssets(), 7323);
    assertEq(pool20.balanceOf(investor3), 2000);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 2322);
    assertEq(pool20.balanceOf(investor2), 4306);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 5000);

    // 9. investor3 withdraws 2322 assets (2000 shares)
    // NOTE: investor 2's assets have been rounded back up
    vm.prank(investor3);
    pool.withdraw(2322, investor3, investor3);

    assertEq(wFIL.balanceOf(investor3), 4433);
    assertEq(pool20.totalSupply(), 4306);
    assertEq(pool.totalAssets(), 5001);
    assertEq(pool20.balanceOf(investor3), 0);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 0);
    assertEq(pool20.balanceOf(investor2), 4306);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 5001);

    // 10. investor2 redeem 4306 shares (5001 tokens)
    vm.prank(investor2);
    pool.redeem(4306, investor2, investor2);
    assertEq(wFIL.balanceOf(investor2), 6968);
    assertEq(pool20.totalSupply(), 0);
    assertEq(pool.totalAssets(), 0);
    assertEq(pool20.balanceOf(investor3), 0);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor3)), 0);
    assertEq(pool20.balanceOf(investor2), 0);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), 0);

    // Sanity check
    assertEq(wFIL.balanceOf(address(pool)), 0);
  }

  function testFailDepositWithNotEnoughApproval() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool), 0.5e18);
        assertEq(wFIL.allowance(address(this), address(pool)), 0.5e18);

        pool.deposit(1e18, address(this));
    }

    function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool), 0.5e18);

        pool.deposit(0.5e18, address(this));

        pool.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughShareAmount() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool), 0.5e18);

        pool.deposit(0.5e18, address(this));

        pool.redeem(1e18, address(this), address(this));
    }

    function testFailWithdrawWithNoUnderlyingAmount() public {
        pool.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNoShareAmount() public {
        pool.redeem(1e18, address(this), address(this));
    }

    function testFailDepositWithNoApproval() public {
        pool.deposit(1e18, address(this));
    }

    function testFailMintWithNoApproval() public {
      vm.prank(investor1);
      pool.mint(1e18, address(this));
      vm.stopPrank();
    }

    function testFailDepositZero() public {
        pool.deposit(0, address(this));
    }

    function testMintZero() public {
      vm.prank(investor1);
      vm.expectRevert("ZERO_ASSETS");
      pool.mint(0, address(this));
      vm.stopPrank();
    }

    function testFailRedeemZero() public {
        pool.redeem(0, address(this), address(this));
    }

    function testWithdrawZero() public {
        pool.withdraw(0, address(this), address(this));

        assertEq(pool20.balanceOf(address(this)), 0);
        assertEq(pool.convertToAssets(pool20.balanceOf(address(this))), 0);
        assertEq(pool20.totalSupply(), 0);
        assertEq(pool.totalAssets(), 0);
    }
}

contract PoolBorrowingTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

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
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));
  }

  function testBorrow() public {
    vm.startPrank(investor1);

    wFIL.approve(address(pool.template()), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();
    uint256 prevMinerBal = wFIL.balanceOf(address(agent));

    uint256 powerAmtStake = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);

    uint256 startEpoch = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    uint256 postMinerBal = wFIL.balanceOf(address(agent));

    vm.stopPrank();

    assertEq(postMinerBal - prevMinerBal, borrowAmount);

    Account memory account = pool.getAccount(address(agent));
    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, startEpoch);
    assertGt(account.pmtPerPeriod, 0);

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));
    assertEq(poolPowTokenBal, powerAmtStake);
    assertEq(agentPowTokenBal, signedCred.vc.miner.qaPower - powerAmtStake);
    assertEq(poolPowTokenBal + agentPowTokenBal, signedCred.vc.miner.qaPower);
  }

  function testMultiBorrowNoDeficit() public {

  }

  // tests a deficit < borrow amt
  function testBorrowDeficitWAdditionalProceeds() public {}

  // tests a deficit > borrow amt
  function testBorrowDeficitNoProceeds() public {}
}

contract PoolExitingTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

  uint256 borrowAmount = 0.5e18;
  uint256 investor1UnderlyingAmount = 1e18;
  address investor1 = makeAddr("INVESTOR1");
  address minerOwner = makeAddr("MINER_OWNER");
  address poolOperator = makeAddr("POOL_OPERATOR");

  string poolName = "POOL_1";
  string poolSymbol = "POOL1";

  uint256 borrowBlock;

  function setUp() public {
    poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
    powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    treasury = IRouter(router).getRoute(ROUTE_TREASURY);
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));

    vm.startPrank(investor1);
    wFIL.approve(address(pool.template()), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    uint256 powerAmtStake = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);

    vm.stopPrank();
  }

  function testFullExit() public {
    vm.prank(address(agent));
    wFIL.approve(address(pool), borrowAmount);
    // NOTE: anyone can exit anyone else - the returned tokens still go to the agent's account
    pool.exitPool(address(agent), signedCred, borrowAmount);

    Account memory account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, 0);
    assertEq(account.powerTokensStaked, 0);
    assertEq(account.startEpoch, 0);
    assertEq(account.pmtPerPeriod, 0);
    assertEq(account.epochsPaid, 0);
    assertEq(pool.totalBorrowed(), 0);
  }

  function testPartialExitWithinCurrentWindow() public {
    vm.prank(address(agent));
    wFIL.approve(address(pool), borrowAmount);

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    pool.exitPool(address(agent), signedCred, borrowAmount / 2);

    uint256 poolPowTokenBalAfter = IERC20(address(powerToken)).balanceOf(address(pool));

    Account memory accountAfter = pool.getAccount(address(agent));

    assertEq(accountAfter.totalBorrowed, borrowAmount / 2);
    assertEq(accountAfter.powerTokensStaked, poolPowTokenBal - poolPowTokenBalAfter);
    assertEq(accountAfter.startEpoch, borrowBlock);
    assertGt(accountAfter.pmtPerPeriod, 0);
    // exiting goes towards principal and does not credit partial payment on account
    assertEq(pool.totalBorrowed(), borrowAmount / 2);
  }
}

contract PoolMakePaymentTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

  uint256 borrowAmount = 0.5e18;
  uint256 powerAmtStake = 1e18;
  uint256 investor1UnderlyingAmount = 1e18;
  address investor1 = makeAddr("INVESTOR1");
  address minerOwner = makeAddr("MINER_OWNER");
  address poolOperator = makeAddr("POOL_OPERATOR");

  string poolName = "POOL_1";
  string poolSymbol = "POOL1";

  uint256 borrowBlock;

  function setUp() public {
    poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
    powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    treasury = IRouter(router).getRoute(ROUTE_TREASURY);
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));

    vm.startPrank(investor1);
    wFIL.approve(address(pool.template()), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);

    vm.stopPrank();
  }

  function testFullPayment() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    wFIL.approve(address(pool), pmtPerPeriod);
    pool.makePayment(address(agent), pmtPerPeriod);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
    assertEq(account.epochsPaid, nextPaymentWindowClose);
  }

  function testPartialPmtWithinCurrentWindow() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    uint256 partialPayment = pmtPerPeriod / 2;
    wFIL.approve(address(pool), partialPayment);
    pool.makePayment(address(agent), partialPayment);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();

    assertEq(account.epochsPaid, GetRoute.agentPolice(router).windowLength() / 2, "Account epochsPaid shold be half the window length");
    assertLt(account.epochsPaid, nextPaymentWindowClose, "Account epochsPaid should be less than the nextPmtWindowDeadline");
  }

  function testForwardPayment() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    uint256 forwardPayment = pmtPerPeriod * 2;
    wFIL.approve(address(pool), forwardPayment);
    pool.makePayment(address(agent), forwardPayment);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();

    assertEq(account.epochsPaid, nextPaymentWindowClose * 2, "Account epochsPaid should be 2 nextPmtWindowDeadlines forward");
  }

  function testMultiPartialPaymentsToPmtPerPeriod() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    wFIL.approve(address(pool), pmtPerPeriod);

    uint256 partialPayment = pmtPerPeriod / 2;
    pool.makePayment(address(agent), partialPayment);

    // roll forward in time for shits and gigs
    vm.roll(block.number + 1);

    pool.makePayment(address(agent), partialPayment);
    vm.stopPrank();

    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();

    assertEq(account.epochsPaid, nextPaymentWindowClose, "Account epochsPaid should be the nextPmtWindowDeadline");
  }

  function testLatePayment() public {
    IAgentPolice police = GetRoute.agentPolice(router);
    // capture original next payment deadline
    uint256 originalPaymentClose = police.nextPmtWindowDeadline();

    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");

    // fast forward 2 window deadlines
    vm.roll(block.number + police.windowLength()*2);

    uint256 pmtPerPeriod = account.pmtPerPeriod;
    wFIL.approve(address(pool), pmtPerPeriod);


    pool.makePayment(address(agent), pmtPerPeriod);
    vm.stopPrank();

    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    uint256 nextWindowClose = police.nextPmtWindowDeadline();
    assertEq(account.epochsPaid, originalPaymentClose, "Account epochsPaid should be the original payment close, the account should not be up to date");
    assertLt(originalPaymentClose, nextWindowClose, "The next payment window should be greater than the original payment window");
  }
}

contract PoolStakeToPayTest is BaseTest {
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

  uint256 borrowAmount = 0.5e18;
  uint256 powerAmtStake = 1e18;
  uint256 investor1UnderlyingAmount = 1e18;
  address investor1 = makeAddr("INVESTOR1");
  address minerOwner = makeAddr("MINER_OWNER");
  address poolOperator = makeAddr("POOL_OPERATOR");

  string poolName = "POOL_1";
  string poolSymbol = "POOL1";

  uint256 borrowBlock;

  function setUp() public {
    poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
    powerToken = IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    treasury = IRouter(router).getRoute(ROUTE_TREASURY);
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));

    vm.startPrank(investor1);
    wFIL.approve(address(pool.template()), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.miner.qaPower, signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);

    vm.stopPrank();
  }

  function testFullPayment() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    pool.stakeToPay(pmtPerPeriod, signedCred, powerAmtStake);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount + pmtPerPeriod);
    // double power was staked
    assertEq(account.powerTokensStaked, powerAmtStake * 2);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount + pmtPerPeriod);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
    assertEq(account.epochsPaid, nextPaymentWindowClose);
  }

  function testPartialPmtWithinCurrentWindow() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    uint256 partialPayment = pmtPerPeriod / 2;
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    pool.stakeToPay(partialPayment, signedCred, powerAmtStake);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount + partialPayment);
    assertEq(account.powerTokensStaked, powerAmtStake * 2);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount + partialPayment);

    // since we paid exactly half of what we owe, epochsPaid should be windowLength / 2
    assertEq(account.epochsPaid, GetRoute.agentPolice(router).windowLength() / 2, "Account epochsPaid should be greater than 0");
  }

  function testForwardPayment() public {
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");
    uint256 pmtPerPeriod = account.pmtPerPeriod;
    uint256 forwardPayment = pmtPerPeriod * 2;
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    pool.stakeToPay(forwardPayment, signedCred, powerAmtStake);
    vm.stopPrank();
    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount + forwardPayment);
    assertEq(account.powerTokensStaked, powerAmtStake * 2);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount + forwardPayment);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();

    assertEq(account.epochsPaid, nextPaymentWindowClose * 2, "Account epochsPaid should be 2 nextPmtWindowDeadlines forward");
  }

  function testLatePayment() public {
    IAgentPolice police = GetRoute.agentPolice(router);
    vm.startPrank(address(agent));
    Account memory account = pool.getAccount(address(agent));
    assertEq(account.epochsPaid, 0, "Account should not have epochsPaid > 0 before making a payment");

    // fast forward 2 window deadlines
    vm.roll(block.number + police.windowLength()*2);

    uint256 pmtPerPeriod = account.pmtPerPeriod;
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    // issue new cred in valid epoch range
    signedCred = issueGenericSC(address(agent));

    try pool.stakeToPay(pmtPerPeriod, signedCred, powerAmtStake) {
      assertTrue(false, "testTransferPoolNonAgent should revert.");
    } catch (bytes memory err) {
      (,,,,,string memory reason) = Decode.insufficientPowerError(err);

      assertEq(reason, "PoolTemplate: additional power insufficient to make payment to bring account current", "reason should be the expected reason");
    }

    vm.stopPrank();

    account = pool.getAccount(address(agent));

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerPeriod, pmtPerPeriod);
    assertEq(pool.totalBorrowed(), borrowAmount);
    assertEq(account.epochsPaid, 0, "Account epochsPaid should not have changed");
  }

  function testChangedPmtPerPeriod() internal {}
}
