// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Decode} from "src/Errors.sol";
import {PoolAccounting} from "src/Pool/PoolAccounting.sol";
import {Roles} from "src/Constants/Roles.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {ROUTE_POOL_FACTORY_ADMIN} from "src/Constants/Routes.sol";
import "./BaseTest.sol";

// a value we use to test approximation of the cursor according to a window start/close
// TODO: investigate how to get this to 0 or 1
uint256 constant EPOCH_CURSOR_ACCEPTANCE_DELTA = 1;

contract PoolTemplateStakingTest is BaseTest {
  using Credentials for VerifiableCredential;
  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  IPool pool;
  IERC20 pool20;
  IERC20 iou;

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
    iou = IERC20(address(pool.iou()));

    vm.deal(investor1, 10e18);
    vm.prank(investor1);
    wFIL.deposit{value: 10e18}();
    require(wFIL.balanceOf(investor1) == 10e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));
  }

  function testAsset() public {
    ERC20 asset = pool.asset();
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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    assertEq(wFIL.allowance(investor1, address(pool)), investor1UnderlyingAmount, "investor1 allowance");

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    uint256 investor1ShareAmount = pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();
    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
    assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount, "Preview Depost = investor1 share amount");
    assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");


    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
    assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
    assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");

    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount, "investor1 balance of underlying = investor1 pre deposit balance - investor1 underlying amount");

    vm.prank(investor1);
    pool.withdraw(investor1UnderlyingAmount, investor1, investor1);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), 0, "convertToAssets = 0");

    assertEq(pool20.balanceOf(investor1), 0,  "Investor 1 balance of pool token = 0");
    assertEq(pool.ramp().iouTokensStaked(investor1), investor1UnderlyingAmount, "investor1 IOU balance = investor1 underlying amount");

  }

  function testDepositFil() public {
    uint256 investor1UnderlyingAmount = 1e18;
    vm.deal(investor1, investor1UnderlyingAmount);
    vm.startPrank(investor1);
    uint256 investor1ShareAmount = pool.deposit{value: investor1UnderlyingAmount}(investor1);
    assertEq(wFIL.balanceOf(address(pool)), investor1UnderlyingAmount, "pool wfil balance = investor1 underlying amount");
    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
    // assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
    // assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");

    // assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
    // assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
    // assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");
  }

  function testSendFilIntoPool() public {
    uint256 investor1UnderlyingAmount = 1e18;
    vm.deal(investor1, investor1UnderlyingAmount);
    vm.startPrank(investor1);
    address(pool).call{value: investor1UnderlyingAmount}("");
    assertEq(wFIL.balanceOf(address(pool)), investor1UnderlyingAmount, "pool wfil balance = investor1 underlying amount");
    uint256 investor1ShareAmount = pool20.balanceOf(investor1);
    // Expect exchange rate to be 1:1 on initial deposit.
    assertEq(investor1UnderlyingAmount, investor1ShareAmount, "underlying amount = investor1 share amount");
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount, "Preview Withdraw = investor1 underlying amount");
    assertEq(pool.totalAssets(), investor1UnderlyingAmount, "total assets = investor1 underlying amount");

    assertEq(pool.convertToAssets(pool20.balanceOf(investor1)), investor1UnderlyingAmount, "convertToAssets = investor1 underlying amount");
    assertEq(pool20.balanceOf(investor1), investor1ShareAmount, "Investor 1 balance of pool token = investor1 share amount");
    assertEq(pool20.totalSupply(), investor1ShareAmount, "Pool token total supply = investor1 share amount");
  }

  function testSingleMintRedeem() public {
    uint256 investor1ShareAmount = 1e18;

    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

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

    assertEq(pool20.balanceOf(investor1), 0);
    assertEq(pool.ramp().iouTokensStaked(investor1), investor1UnderlyingAmount);

  }

  function testFailDepositWithNotEnoughApproval() public {
        wFIL.deposit{value: 0.5e18}();
        wFIL.approve(address(pool), 0.5e18);
        assertEq(wFIL.allowance(address(this), address(pool)), 0.5e18);

        pool.deposit(1e18, address(this));
    }

  function testMintForReceiver() public {
    uint256 investor1ShareAmount = 1e18;

    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    uint256 investor1UnderlyingAmount = pool.mint(investor1ShareAmount, investor2);
    vm.stopPrank();
    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(investor1ShareAmount, investor1UnderlyingAmount);
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor1UnderlyingAmount);
    assertEq(pool.totalAssets(), investor1UnderlyingAmount);

    assertEq(pool20.totalSupply(), investor1ShareAmount);
    assertEq(pool20.balanceOf(investor2), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);
  }

  function testDepositForReceiver() public {
    uint256 investor1UnderlyingAmount = 1e18;
    uint256 investor1ShareAmount = pool.previewDeposit(investor1UnderlyingAmount);

    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1ShareAmount);
    assertEq(wFIL.allowance(investor1, address(pool)), investor1ShareAmount);

    uint256 investor1PreDepositBal = wFIL.balanceOf(investor1);

    pool.deposit(investor1UnderlyingAmount, investor2);
    vm.stopPrank();
    // Expect exchange rate to be 1:1 on initial mint.
    assertEq(investor1ShareAmount, investor1UnderlyingAmount);
    assertEq(pool.previewWithdraw(investor1ShareAmount), investor1UnderlyingAmount);
    assertEq(pool.previewDeposit(investor1UnderlyingAmount), investor1ShareAmount);
    assertEq(pool.convertToAssets(pool20.balanceOf(investor2)), investor1UnderlyingAmount);
    assertEq(pool.totalAssets(), investor1UnderlyingAmount);

    assertEq(pool20.totalSupply(), investor1ShareAmount);
    assertEq(pool20.balanceOf(investor2), investor1UnderlyingAmount);
    assertEq(wFIL.balanceOf(investor1), investor1PreDepositBal - investor1UnderlyingAmount);
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
      vm.expectRevert("Pool: cannot mint 0 shares");
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
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

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

    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();
    uint256 prevMinerBal = wFIL.balanceOf(address(agent));

    uint256 powerAmtStake = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);

    uint256 startEpoch = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    uint256 postMinerBal = wFIL.balanceOf(address(agent));

    vm.stopPrank();

    assertEq(postMinerBal - prevMinerBal, borrowAmount);

    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, startEpoch);
    assertGt(account.pmtPerEpoch(), 0);

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    uint256 agentPowTokenBal = IERC20(address(powerToken)).balanceOf(address(agent));
    assertEq(poolPowTokenBal, powerAmtStake);
    assertEq(agentPowTokenBal, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - powerAmtStake);
    assertEq(poolPowTokenBal + agentPowTokenBal, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
  }

  function testMultiBorrowNoDeficit() public {

  }

  // tests a deficit < borrow amt
  function testBorrowDeficitWAdditionalProceeds() public {}

  // tests a deficit > borrow amt
  function testBorrowDeficitNoProceeds() public {}


  function testTotalBorrowable() public {

    vm.startPrank(investor1);

    wFIL.approve(address(pool), investor1UnderlyingAmount);
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


    uint256 totalBorrowable = pool.totalBorrowableAssets();
    uint256 totalBorrowed = pool.totalBorrowed();
    assertEq(totalBorrowed, borrowAmount);
    assertEq(totalBorrowable, investor1UnderlyingAmount - borrowAmount);
  }
}

contract PoolExitingTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    uint256 powerAmtStake = 1e18;
    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
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
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, 0);
    assertEq(account.powerTokensStaked, 0);
    assertEq(account.startEpoch, 0);
    assertEq(account.pmtPerEpoch(), 0);
    assertEq(account.epochsPaid, 0);
    assertEq(pool.totalBorrowed(), 0);
  }

  function testPartialExitWithinCurrentWindow() public {
    vm.prank(address(agent));
    wFIL.approve(address(pool), borrowAmount);

    uint256 poolPowTokenBal = IERC20(address(powerToken)).balanceOf(address(pool));
    pool.exitPool(address(agent), signedCred, borrowAmount / 2);

    uint256 poolPowTokenBalAfter = IERC20(address(powerToken)).balanceOf(address(pool));

    Account memory accountAfter = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(accountAfter.totalBorrowed, borrowAmount / 2);
    assertEq(accountAfter.powerTokensStaked, poolPowTokenBal - poolPowTokenBalAfter);
    assertEq(accountAfter.startEpoch, borrowBlock);
    assertGt(accountAfter.pmtPerEpoch(), 0);
    // exiting goes towards principal and does not credit partial payment on account
    assertEq(pool.totalBorrowed(), borrowAmount / 2);
  }
}

contract PoolMakePaymentTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  IAgent agent;
  IAgentPolice police;


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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    vm.stopPrank();

    police = GetRoute.agentPolice(router);
  }

  function testFullPayment() public {
    vm.startPrank(address(agent));

    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    // This should be equal to the window start, not necesarily 0 - same is true of all instances
    assertEq(account.epochsPaid, police.windowInfo().start, "Account should not have epochsPaid > window.start before making a payment");
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());
    wFIL.approve(address(pool), minPaymentToCloseWindow);
    pool.makePayment(address(agent), minPaymentToCloseWindow);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
    assertApproxEqAbs(
      account.epochsPaid,
      nextPaymentWindowClose,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account should have paid up to the end of the next payment window"
    );
    assertTrue(account.epochsPaid >= nextPaymentWindowClose);
  }

  function testPartialPmtWithinCurrentWindow() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());
    // Round up to ensure we don't pay less than the minimum
    uint256 partialPayment = minPaymentToCloseWindow / 2 + (minPaymentToCloseWindow % 2);
    wFIL.approve(address(pool), partialPayment);
    pool.makePayment(address(agent), partialPayment);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount, "Account total borrowed should not change");
    assertEq(account.powerTokensStaked, powerAmtStake, "Account power tokens staked should not change");
    assertEq(account.startEpoch, borrowBlock, "Account start epoch should not change");
    assertEq(account.pmtPerEpoch(), pmtPerEpoch, "Account payment per epoch should not change");
    assertEq(pool.totalBorrowed(), borrowAmount, "Pool total borrowed should not change");

    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    assertApproxEqAbs(
      account.epochsPaid,
      (window.start) + window.length / 2,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid shold be half the window length"
    );
    assertTrue(account.epochsPaid >= window.start +  (window.length / 2) );
  }

  function testForwardPayment() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());
    uint256 forwardPayment = minPaymentToCloseWindow * 2;
    wFIL.approve(address(pool), forwardPayment);
    pool.makePayment(address(agent), forwardPayment);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerEpoch(), pmtPerEpoch);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    assertApproxEqAbs(
      account.epochsPaid,
      window.deadline + window.length,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid should be 2 nextPmtWindowDeadlines forward"
    );

    assertTrue(account.epochsPaid >= window.deadline + window.length);
  }

  function testMultiPartialPaymentsToPmtPerPeriod() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(account.epochsPaid, window.start, "Account should not have epochsPaid > window.start before making a payment");
    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());

    uint256 partialPayment = minPaymentToCloseWindow / 2;
    wFIL.approve(address(pool), partialPayment);
    pool.makePayment(address(agent), partialPayment);

    // roll forward in time for shits and gigs
    vm.roll(block.number + 1);
    window = police.windowInfo();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());
    partialPayment = account.getMinPmtForWindowClose(window, router, pool.implementation());
    wFIL.approve(address(pool), partialPayment);

    pool.makePayment(address(agent), partialPayment);
    vm.stopPrank();

    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerEpoch(), pmtPerEpoch);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    assertApproxEqAbs(
      account.epochsPaid,
      window.deadline,
      0,
      "Account epochsPaid should be the nextPmtWindowDeadline"
    );

    assertTrue(account.epochsPaid >= window.deadline);
  }

  function testLatePaymentToCloseCurrentWindow() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );

    // fast forward a window deadlines
    vm.roll(block.number + window.length);

    window = police.windowInfo();

    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());
    wFIL.approve(address(pool), minPaymentToCloseWindow);

    pool.makePayment(address(agent), minPaymentToCloseWindow);
    vm.stopPrank();

    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerEpoch(), pmtPerEpoch);
    assertEq(pool.totalBorrowed(), borrowAmount);

    assertApproxEqAbs(
      account.epochsPaid,
      window.deadline,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid should be the end of the current window."
    );

    assertTrue(account.epochsPaid >= window.deadline);
  }

  function testLatePaymentToGetCurrent() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );
    // fast forward a window period
    vm.roll(block.number + window.length);

    window = police.windowInfo();

    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToGetCurrent = account.getMinPmtForWindowStart(window, router, pool.implementation());
    wFIL.approve(address(pool), minPaymentToGetCurrent);

    pool.makePayment(address(agent), minPaymentToGetCurrent);
    vm.stopPrank();

    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerEpoch(), pmtPerEpoch);
    assertEq(pool.totalBorrowed(), borrowAmount);

    assertApproxEqAbs(
      account.epochsPaid,
      window.start,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid should be the current window start"
    );
    assertTrue(account.epochsPaid >= window.start);
  }
}

contract PoolStakeToPayTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;


  IAgent agent;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  IAgentPolice police;
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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);

    vm.stopPrank();

    police = GetRoute.agentPolice(router);
  }

  function testFullPaymentStaking() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );
    uint256 pmtPerEpoch = account.pmtPerEpoch();
    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(window, router, pool.implementation());
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    // This test is failing because of the shift in the total amount borrowed mid-call
    // The payment per epoch is reliant on the total amount borrowed so it messes up the math.
    pool.stakeToPay(minPaymentToCloseWindow, signedCred, powerAmtStake);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount + minPaymentToCloseWindow, "Account should have borrowed more funds");
    // double power was staked
    assertEq(account.powerTokensStaked, powerAmtStake * 2, "Account should have staked more power tokens");
    assertEq(account.startEpoch, borrowBlock, "Account should have the same startEpoch");
    assertEq(pool.totalBorrowed(), borrowAmount + minPaymentToCloseWindow, "Pool should have loaned more funds");
    // since we ended up borrowing more funds, the payment per epoch should increase
    // meaning the account should not be fully paid for the current cycle
    assertApproxEqAbs(
      account.epochsPaid,
      window.deadline,
      0,
      "Account epochsPaid should be the next payment window close"
    );
    assertTrue(account.epochsPaid >= window.deadline, "Account epochsPaid should be the next payment window close");
    assertGt(account.pmtPerEpoch(), pmtPerEpoch, "Account pmtPerEpoch should be greater than before");
  }

  // TODO:
  function testStakeToPayOffCurrentCycle() public {}

  function testPartialPmtWithinCurrentWindow() public {
    vm.startPrank(address(agent));

    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );

    uint256 partialPayment = account._getMinPmtForEpochCursor(
      (window.deadline + window.start) / 2,
      router,
      window,
      pool.implementation()
    );

    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    pool.stakeToPay(partialPayment, signedCred, powerAmtStake);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount + partialPayment);
    assertEq(account.powerTokensStaked, powerAmtStake * 2);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(pool.totalBorrowed(), borrowAmount + partialPayment);

    // since we paid exactly half of what we owe, epochsPaid should be windowLength / 2
    assertApproxEqAbs(
      account.epochsPaid,
      (window.start + window.deadline) / 2,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid should be less than half the window length"
    );

    assertGt(account.epochsPaid, window.start, "Account epochsPaid should be greater than window start");
  }

  function testForwardStakedPayment() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );
    uint256 forwardPayment = account._getMinPmtForEpochCursor(
      window.deadline + window.length + 1,
      router,
      window,
      pool.implementation()
    );
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    pool.stakeToPay(forwardPayment, signedCred, powerAmtStake);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount + forwardPayment);
    assertEq(account.powerTokensStaked, powerAmtStake * 2);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(pool.totalBorrowed(), borrowAmount + forwardPayment);

    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    assertApproxEqAbs(
      account.epochsPaid,
      window.deadline + window.length,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account epochsPaid should be 2 nextPmtWindowDeadlines forward"
    );
    assertGt(account.epochsPaid, window.start);
  }

  function testLatePayment() public {
    vm.startPrank(address(agent));
    Window memory window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(
      account.epochsPaid,
      window.start,
      "Account should not have epochsPaid > window.start before making a payment"
    );

    // fast forward a window period
    vm.roll(block.number + police.windowLength());

    uint256 pmtPerEpoch = account.pmtPerEpoch();
    IERC20(address(powerToken)).approve(address(pool), powerAmtStake);
    // issue new cred in valid epoch range
    signedCred = issueGenericSC(address(agent));

    try pool.stakeToPay(pmtPerEpoch, signedCred, powerAmtStake) {
      assertTrue(false, "testTransferPoolNonAgent should revert.");
    } catch (bytes memory err) {
      (,,,,,string memory reason) = Decode.insufficientPaymentError(err);

      assertEq(reason, "PoolTemplate: Payment size too small");
    }

    vm.stopPrank();

    account = AccountHelpers.getAccount(router, address(agent), pool.id());
    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(account.pmtPerEpoch(), pmtPerEpoch);
    assertEq(pool.totalBorrowed(), borrowAmount);
    assertEq(account.epochsPaid, window.start, "Account epochsPaid should not have changed");
  }

  // TODO:
  function testLatePaymentBackToCurrent() public {}

  function testChangedPmtPerPeriod() internal {}
}

contract PoolPenaltiesTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  IAgent agent;
  IAgentPolice police;


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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    vm.stopPrank();

    police = GetRoute.agentPolice(router);
  }

  function testAccruePenaltyEpochs() public {
    vm.startPrank(address(agent));
    // fast forward 2 window periods
    Window memory window = police.windowInfo();
    vm.roll(block.number + window.length*2);
    window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

    // penalty epochs here should be 1 window length, since we fast forwarded 2 windows
    uint256 penaltyEpochs = account.getPenaltyEpochs(window);
    assertEq(penaltyEpochs, window.length, "Account should have 1 windows length of penalty epochs");
  }

  /// In this example, we fast forward 2 windows, so the Agent owes for 3 total windows
  /// then we make a payment to close the window
  /// since a penalty is paid for 1 window, the pmtPerPeriod * 3 < amount paid
  function testMakePaymentWithPenaltyToCloseWindow() public {
    vm.startPrank(address(agent));

    Window memory window = police.windowInfo();
    vm.roll(block.number + window.length*2);
    window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

    uint256 minPaymentToCloseWindow = account.getMinPmtForWindowClose(police.windowInfo(), router, pool.implementation());
    wFIL.approve(address(pool), minPaymentToCloseWindow);
    pool.makePayment(address(agent), minPaymentToCloseWindow);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(pool.totalBorrowed(), borrowAmount);
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    uint256 nextPaymentWindowClose = GetRoute.agentPolice(router).nextPmtWindowDeadline();
    assertApproxEqAbs(
      account.epochsPaid,
      nextPaymentWindowClose,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account should have paid up to the end of the next payment window"
    );
    assertTrue(account.epochsPaid >= nextPaymentWindowClose);
    assertTrue(minPaymentToCloseWindow >= account.pmtPerPeriod(router) * 3, "Min payment to close window should be greater than 3 period payments");
    // NOTE: this condition isn't always true, if the penalties are large enough. it is true in our test environment
    assertTrue(minPaymentToCloseWindow < account.pmtPerPeriod(router) * 4, "Min payment to close window should be less than than 4 period payments");
  }

  function testMakePaymentWithPenaltyToCurrent() public {
    vm.startPrank(address(agent));

    Window memory window = police.windowInfo();
    vm.roll(block.number + window.length*2);
    window = police.windowInfo();
    Account memory account = AccountHelpers.getAccount(router, address(agent), pool.id());

    uint256 minPayment = account.getMinPmtForWindowStart(police.windowInfo(), router, pool.implementation());
    wFIL.approve(address(pool), minPayment);
    pool.makePayment(address(agent), minPayment);
    vm.stopPrank();
    account = AccountHelpers.getAccount(router, address(agent), pool.id());

    assertEq(account.totalBorrowed, borrowAmount);
    assertEq(account.powerTokensStaked, powerAmtStake);
    assertEq(account.startEpoch, borrowBlock);
    assertEq(pool.totalBorrowed(), borrowAmount);
    uint256 windowStart = police.windowInfo().start;
    // since we paid the full amount, the last payment epoch should be the end of the next payment window
    assertApproxEqAbs(
      account.epochsPaid,
      windowStart,
      EPOCH_CURSOR_ACCEPTANCE_DELTA,
      "Account should have paid up to the end of the next payment window"
    );
    assertTrue(account.epochsPaid >= windowStart);
    assertTrue(minPayment >= account.pmtPerPeriod(router) * 2, "Min payment to close window should be greater than 3 period payments");
    // NOTE: this condition isn't always true, if the penalties are large enough. it is true in our test environment
    assertTrue(minPayment < account.pmtPerPeriod(router) * 3, "Min payment to close window should be less than than 4 period payments");
  }

  function testBorrowInPenalty() public {
    vm.startPrank(address(agent));
    // fast forward 2 window periods
    Window memory window = police.windowInfo();
    vm.roll(block.number + window.length*2);
    window = police.windowInfo();

    SignedCredential memory sc = issueGenericSC(address(agent));
    powerToken.approve(address(pool), powerAmtStake);

    try pool.borrow(borrowAmount, sc, powerAmtStake) {
      assertTrue(false, "Should not be able to borrow in penalty");
    } catch (bytes memory err) {
      (,,, string memory reason) = Decode.unauthorizedError(err);
      assertEq(reason, "PoolTemplate: Cannot perform action while in penalty");
    }
  }
}

contract TreasuryFeesTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  IAgent agent;
  IAgentPolice police;


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
    poolFactory = GetRoute.poolFactory(router);
    powerToken = GetRoute.powerToken(router);
    treasury = GetRoute.treasury(router);
    police = GetRoute.agentPolice(router);

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
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    borrowBlock = block.number;
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    vm.stopPrank();
  }

  function testTreasuryFees() public {
    vm.startPrank(investor1);
    wFIL.approve(address(pool), 1e18);
    pool.makePayment(address(agent), 1e18);
    vm.stopPrank();
    uint256 treasuryBalance = wFIL.balanceOf(treasury);
    assertEq(treasuryBalance, (1e18 * .10), "Treasury should have received 10% fees");
  }
}

contract PoolUpgradeTest is BaseTest {
  using AccountHelpers for Account;
  using Credentials for VerifiableCredential;

  IAgent agent;
  IAgentPolice police;

  IPoolFactory poolFactory;
  IPowerToken powerToken;
  // this isn't ideal but it also prepares us better to separate the pool token from the pool
  IPool pool;
  IERC20 pool20;

  SignedCredential signedCred;

  uint256 borrowAmount = 5e18;
  uint256 powerAmtStake = 1e18;
  uint256 investor1UnderlyingAmount = 10e18;
  address investor1 = makeAddr("INVESTOR1");
  address minerOwner = makeAddr("MINER_OWNER");
  address poolOperator = makeAddr("POOL_OPERATOR");

  string poolName = "POOL_1";
  string poolSymbol = "POOL1";

  function setUp() public {
    poolFactory = GetRoute.poolFactory(router);
    powerToken = GetRoute.powerToken(router);
    treasury = GetRoute.treasury(router);
    police = GetRoute.agentPolice(router);
    pool = createPool(
      poolName,
      poolSymbol,
      poolOperator,
      20e18
    );
    pool20 = IERC20(address(pool.share()));

    vm.deal(investor1, 100e18);
    vm.prank(investor1);
    wFIL.deposit{value: 100e18}();
    require(wFIL.balanceOf(investor1) == 100e18);

    (agent,) = configureAgent(minerOwner);

    signedCred = issueGenericSC(address(agent));

    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
    // approve the pool to pull the agent's power tokens on call to deposit
    // note that borrow
    powerToken.approve(address(pool), powerAmtStake);
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    vm.stopPrank();
  }

  function testSetRamp() public {
    address newRamp = makeAddr("NEW_RAMP");
    vm.prank(poolOperator);
    pool.setRamp(IOffRamp(newRamp));
    assertEq(address(pool.ramp()), newRamp, "Ramp should be set");
  }

  function testEnablePoolOperator() public {
    address operator = makeAddr("OPERATOR");
    vm.prank(poolOperator);
    pool.setOperatorRole(operator, true);
    MultiRolesAuthority customAuthority = MultiRolesAuthority(address(coreAuthority.getTargetCustomAuthority(address(pool))));
    assertTrue(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_POOL_OPERATOR)));
  }

  function testDisablePoolOperator() public {
    address operator = makeAddr("OPERATOR");
    vm.prank(poolOperator);
    pool.setOperatorRole(operator, true);
    MultiRolesAuthority customAuthority = MultiRolesAuthority(address(coreAuthority.getTargetCustomAuthority(address(pool))));
    assertTrue(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_POOL_OPERATOR)));

    vm.prank(operator);
    pool.setOperatorRole(operator, false);
    assertTrue(!(customAuthority.doesUserHaveRole(operator, uint8(Roles.ROLE_POOL_OPERATOR))));
  }

  function testShutDown() public {
    assertTrue(!pool.isShuttingDown(), "Pool should not be shut down");
    vm.prank(poolOperator);
    pool.shutDown();
    assertTrue(pool.isShuttingDown(), "Pool should be shut down");
  }

  function testSetTemplate() public {
    address newTemplate = makeAddr("NEW_TEMPLATE");
    // expect this call to revert because the template is not approved
    vm.expectRevert("Pool: Invalid template");
    vm.prank(poolOperator);
    pool.setTemplate(IPoolTemplate(newTemplate));

    // approve the template
    vm.prank(IRouter(router).getRoute(ROUTE_POOL_FACTORY_ADMIN));
    poolFactory.approveTemplate(newTemplate);

    // now this should work
    vm.prank(poolOperator);
    pool.setTemplate(IPoolTemplate(newTemplate));
    assertEq(address(pool.template()), newTemplate, "Template should be set");
  }

  function testSetMinimumLiquidity() public {
    uint256 newMinLiq = 1.3e18;
    vm.prank(poolOperator);
    pool.setMinimumLiquidity(newMinLiq);
    assertEq(pool.minimumLiquidity(), newMinLiq, "Minimum liquidity should be set");
  }

  function testUpgradePool() public {
    // at this point, the pool has 1 staker, and 1 borrower

    // get stats before upgrade
    uint256 investorPoolShares = pool.share().balanceOf(investor1);
    uint256 totalBorrowed = pool.totalBorrowed();
    uint256 agentBorrowed = pool.getAgentBorrowed(agent.id());

    // first shut down the pool
    vm.startPrank(poolOperator);
    pool.shutDown();
    // then upgrade it
    pool = poolFactory.upgradePool(pool.id());
    vm.stopPrank();

    uint256 investorPoolSharesNew = pool.share().balanceOf(investor1);
    uint256 totalBorrowedNew = pool.totalBorrowed();
    uint256 agentBorrowedNew = pool.getAgentBorrowed(agent.id());

    assertEq(investorPoolSharesNew, investorPoolShares);
    assertEq(totalBorrowedNew, totalBorrowed);
    assertEq(agentBorrowedNew, agentBorrowed);

    // now attempt to deposit and borrow again
    vm.startPrank(investor1);
    wFIL.approve(address(pool), investor1UnderlyingAmount);
    pool.deposit(investor1UnderlyingAmount, investor1);
    vm.stopPrank();

    vm.startPrank(address(agent));
    powerToken.approve(address(pool), powerAmtStake);
    pool.borrow(borrowAmount, signedCred, powerAmtStake);
    vm.stopPrank();

    investorPoolSharesNew = pool.share().balanceOf(investor1);
    totalBorrowedNew = pool.totalBorrowed();
    agentBorrowedNew = pool.getAgentBorrowed(agent.id());

    assertGt(investorPoolSharesNew, investorPoolShares);
    assertGt(totalBorrowedNew, totalBorrowed);
    assertGt(agentBorrowedNew, agentBorrowed);
  }
}
