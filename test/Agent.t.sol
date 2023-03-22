// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "test/helpers/MockMiner.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {WFIL} from "src/WFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IRouterAware} from "src/Types/Interfaces/IRouter.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {ROUTE_AGENT_FACTORY_ADMIN, ROUTE_MINER_REGISTRY} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
import {Roles} from "src/Constants/Roles.sol";
import {errorSelector} from "test/helpers/Utils.sol";
import {Decode, InvalidCredential, OverPowered} from "src/Errors.sol";
import {
  Unauthorized,
  InvalidPower,
  InsufficientFunds,
  InsufficientCollateral,
  InvalidParams,
  Internal,
  BadAgentState
} from "src/Agent/Errors.sol";
import "src/Constants/FuncSigs.sol";

import "./BaseTest.sol";

contract AgentBasicTest is BaseTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    Agent agent;
    function setUp() public {
        miner = _newMiner(minerOwner1);
        agent = _configureAgent(minerOwner1, miner);
    }

    function assertAgentPermissions(address operator, address owner, address agent) public {
      assertEq(Agent(payable(agent)).owner(), owner, "wrong owner");
      assertEq(Agent(payable(agent)).operator(), operator, "wrong operator");
    }

    function testInitialState() public {
      assertAgentPermissions(minerOwner1, minerOwner1, address(agent));
    }

    function testAddMinerNonOwnerOperator() public {
      SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), miner);
      vm.startPrank(investor1);
      try agent.addMiner(addMinerCred) {
        assertTrue(false, "should have failed - unauthorized");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), Agent.Unauthorized.selector);
      }
    }

    function testAddDuplicateMiner() public {
      // hack to get the miner's next_owner to be the agent again so we can attempt to add duplicate miners without running into other errors
      // although i dont think this situation could ever occur (because agent would already own the miner at this point)
      vm.startPrank(address(agent));
      miner.changeOwnerAddress(address(agent));
      vm.stopPrank();

      SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), miner);

      vm.startPrank(minerOwner1);
      try agent.addMiner(addMinerCred) {
        assertTrue(false, "should have failed - duplicate miner");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), MinerRegistry.InvalidParams.selector);
      }

      vm.stopPrank();
    }

    function testTransferOwner() public {
      address owner = makeAddr("OWNER");
      vm.prank(minerOwner1);
      agent.transferOwnership(owner);
      assertEq(agent.pendingOwner(), owner);
      vm.prank(owner);
      agent.acceptOwnership();
      assertEq(agent.owner(), owner);
    }

    function testTransferOperator() public {
      address operator = makeAddr("OPERATOR");
      vm.prank(minerOwner1);
      agent.transferOperator(operator);
      assertEq(agent.pendingOperator(), operator);
      vm.prank(operator);
      agent.acceptOperator();
      assertEq(agent.operator(), operator);
    }

    function testRouterConfigured() public {
      address r = IRouterAware(address(agent)).router();
      assertEq(IRouterAware(address(agent)).router(), address(r));
    }

    function testReceive() public {
      uint256 transferAmt = 1e18;

      vm.deal(investor1, transferAmt);
      (Agent agent,) = configureAgent(investor1);
      uint256 agentFILBal = address(agent).balance;

      vm.prank(investor1);
      (bool sent,) = payable(address(agent)).call{value: transferAmt}("");
      assertTrue(sent);
      assertEq(address(agent).balance, agentFILBal + transferAmt);
    }

    function testFallback() public {
      uint256 transferAmt = 1e18;

      vm.deal(investor1, transferAmt);
      (Agent agent,) = configureAgent(investor1);
      uint256 agentFILBal = address(agent).balance;

      vm.prank(investor1);
      (bool sent,) = payable(address(agent)).call{value: transferAmt}(bytes("fdsa"));
      assertTrue(sent);
      assertEq(address(agent).balance, agentFILBal + transferAmt);
    }

    function testSingleUseCredentials() public {
      // testing that single use credentials are consumed through pushFundsToMiner call
      uint256 pushAmount = 1e18;
      vm.deal(address(agent), pushAmount);
      SignedCredential memory pushFundsCred = issuePushFundsToMinerCred(agent.id(), miner, pushAmount);

      vm.startPrank(minerOwner1);
      agent.pushFundsToMiner(pushFundsCred);

      try agent.pushFundsToMiner(pushFundsCred) {
        assertTrue(false, "should have failed - single use credential");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
      }

      vm.stopPrank();
    }
}

contract AgentPushPullFundsTest is BaseTest {
    using Credentials for VerifiableCredential;
    using MinerHelper for uint64;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner1 = makeAddr("MINER_OWNER_1");

    uint64 miner;
    Agent agent;
    function setUp() public {
        miner = _newMiner(minerOwner1);
        agent = _configureAgent(minerOwner1, miner);
    }

    function testPullFundsFromMiner(uint256 drawAmount) public {
      vm.assume(drawAmount > 0.001e18);
      uint256 preAgentBal = address(agent).balance;

      address miner1 = idStore.ids(miner);
      // give the miner some funds to pull
      vm.deal(miner1, drawAmount);

      assertEq(wFIL.balanceOf(address(agent)), 0);
      SignedCredential memory pullFundsCred = issuePullFundsFromMinerCred(agent.id(), miner, drawAmount);
      vm.startPrank(minerOwner1);
      agent.pullFundsFromMiner(pullFundsCred);
      vm.stopPrank();
      assertEq(address(agent).balance, drawAmount + preAgentBal);
      assertEq(miner1.balance, 0);
    }

    function testPushFundsToMiner(uint256 pushAmount) public {
      vm.assume(pushAmount > 0.001e18);
      require(address(agent).balance == 0);

      address miner1 = idStore.ids(miner);
      // give the agent some funds to pull
      vm.deal(address(agent), pushAmount);

      SignedCredential memory pushFundsCred = issuePushFundsToMinerCred(agent.id(), miner, pushAmount);
      vm.prank(minerOwner1);
      agent.pushFundsToMiner(pushFundsCred);
      vm.stopPrank();

      assertEq(address(agent).balance, 0);
      assertEq(miner1.balance, pushAmount);
    }

    function testPushFundsToRandomMiner() public {
      uint64 secondMiner = _newMiner(minerOwner1);
      address miner2 = idStore.ids(secondMiner);

      SignedCredential memory pushFundsCred = issuePushFundsToMinerCred(agent.id(), secondMiner, 1e18);
      vm.startPrank(minerOwner1);
      try agent.pushFundsToMiner(pushFundsCred) {
          assertTrue(false, "should not be able to push funds to random miners");
      } catch (bytes memory b) {
          assertEq(errorSelector(b), Unauthorized.selector);
      }

      vm.stopPrank();
    }

    function testPullFundsWithWrongCred() public {
      SignedCredential memory pullFundsCred = issuePullFundsFromMinerCred(agent.id(), miner, 0);
      vm.startPrank(minerOwner1);
      try agent.pushFundsToMiner(pullFundsCred) {
        assertTrue(false, "should not be able to pull funds with wrong cred");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), VCVerifier.InvalidCredential.selector);
      }
    }

    function testPushFundsWithWrongCred() public {
      SignedCredential memory pullFundsCred = issuePushFundsToMinerCred(agent.id(), miner, 0);
      vm.startPrank(minerOwner1);
      try agent.pullFundsFromMiner(pullFundsCred) {
        assertTrue(false, "should not be able to pull funds with wrong cred");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), VCVerifier.InvalidCredential.selector);
      }
    }
}

contract AgentWithdrawTest is BaseTest {
  function testWithdrawWithNoLoans(uint256 withdrawAmount) internal {}

  function testWithdrawWithLoans(uint256 withdrawAmount) internal {}

  function testWithdrawIntoOverLeveragedLTV(uint256 withdrawAmount) internal {}

  function testWithdrawIntoOverLeveragedDTI(uint256 withdrawAmount) internal {}

  function testWithdrawMoreThanLiquid(uint256 withdrawAmount) internal {}
}

contract AgentRmMinerTest is BaseTest {
  function testRmMinerWithNoLoans() internal {}

  function testRmMinerWithLoans() internal {}

  function testRmMinerIntoOverLeveragedLTV() internal {}

  function testRmMinerIntoOverLeveragedDTI() internal {}
}

contract AgentBorrowingTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

    function testBorrowValid(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, DUST, stakeAmount);
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      agentBorrow(agent, pool.id(), borrowCred);
    }

    function testBorrowTwice(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, DUST, stakeAmount / 2);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      uint256 borrowBlock = block.number;
      agentBorrow(agent, pool.id(), borrowCred);
      // roll forward to test the startEpoch and epochsPaid
      vm.roll(block.number + 1000);

      borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      // Since we've already borrowed the borrow amount we need the principle value to increase 4x
      uint256 principle = borrowAmount * 4;
      AgentData memory agentData = createAgentData(
        principle,
        80,
        (rateArray[80] * EPOCHS_IN_DAY * principle * 2) / 1e18,
        // principal = borrowAmount
        borrowAmount,
        // Account started at previous borrow block
        borrowBlock
      );
      borrowCred.vc.claim = abi.encode(agentData);
      borrowCred = signCred(borrowCred.vc);
      agentBorrow(agent, pool.id(), borrowCred);

      Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
      assertEq(account.principal, borrowAmount * 2);
      assertEq(account.startEpoch, borrowBlock);
      assertEq(account.epochsPaid, borrowBlock);
    }

    function testBorrowMoreThanLiquid(uint256 borrowAmount) public {
      borrowAmount = bound(borrowAmount, stakeAmount + 1, MAX_FIL);

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      vm.startPrank(minerOwner);
      try agent.borrow(pool.id(), borrowCred) {
        assertTrue(false, "should not be able to borrow more than liquid");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), GenesisPool.InsufficientLiquidity.selector);
      }

      vm.stopPrank();
    }

    function testBorrowNothing() public {
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), 0);

      vm.startPrank(minerOwner);
      try agent.borrow(pool.id(), borrowCred) {
        assertTrue(false, "should not be able to borrow 0");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), GenesisPool.InvalidParams.selector);
      }

      vm.stopPrank();
    }

    function testBorrowNonOwnerOperator() public {
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), 1e18);

      vm.startPrank(makeAddr("NON_OWNER_OPERATOR"));
      try agent.borrow(pool.id(), borrowCred) {
        assertTrue(false, "should not be able to borrow more than liquid");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), Agent.Unauthorized.selector);
      }

      vm.stopPrank();
    }

    function testBorrowWrongCred() public {
      SignedCredential memory nonBorrowCred = issueAddMinerCred(agent.id(), 0);

      vm.startPrank(minerOwner);
      try agent.borrow(pool.id(), nonBorrowCred) {
        assertTrue(false, "should not be able to borrow more than liquid");
      } catch (bytes memory b) {
        assertEq(errorSelector(b), VCVerifier.InvalidCredential.selector);
      }

      vm.stopPrank();
    }
}

contract AgentPayTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

    function testPayInterestOnly(uint256 payAmount) public {}

    function testPayInterestAndPartialPrincipal(uint256 payAmount) public {}

    function testPayFullExit(uint256 payAmount) public {}

    function testPayTooMuch(uint256 payAmount) public {}

//     function agentExit(IAgent _agent, uint256 _exitAmount, SignedCredential memory _signedCred, IPool _pool) internal {
//         vm.startPrank(_agentOperator(_agent));
//         // Establsh the state before the borrow
//         StateSnapshot memory preBorrowState;
//         preBorrowState.balanceWFIL = wFIL.balanceOf(address(_agent));
//         preBorrowState.poolBalanceWFIL = wFIL.balanceOf(address(_pool));
//         Account memory account = AccountHelpers.getAccount(router, address(_agent), _pool.id());
//         preBorrowState.powerStake = account.powerTokensStaked;
//         preBorrowState.borrowed = account.totalBorrowed;
//         preBorrowState.powerBalance = IERC20(powerToken).balanceOf(address(_agent));
//         preBorrowState.powerBalancePool = IERC20(powerToken).balanceOf(address(_pool));

//         wFIL.approve(address(_pool), _exitAmount);
//         _agent.exit(_pool.id(), _exitAmount, _signedCred);
//         vm.stopPrank();

//         assertEq(IERC20(address(wFIL)).balanceOf(address(_agent)), preBorrowState.balanceWFIL - _exitAmount);
//         assertEq(IERC20(address(wFIL)).balanceOf(address(_pool)), preBorrowState.poolBalanceWFIL + _exitAmount);

//         account = AccountHelpers.getAccount(router, address(_agent), _pool.id());
//         assertEq(account.totalBorrowed, 0);
//         assertEq(account.powerTokensStaked, 0);
//         assertEq(account.pmtPerEpoch(), 0);
//     }

//     function testExit() public {
//         SignedCredential memory sc = issueGenericSC(address(agent));
//         agentBorrow(
//             agent,
//             borrowAmount,
//             sc,
//             pool,
//             powerToken,
//             sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER))
//         );
//         agentExit(agent, borrowAmount, issueGenericSC(address(agent)), pool);
//     }
//     function testRefinance() public {
//         IPool pool2 = createAndPrimePool(
//             "TEST",
//             "TEST",
//             poolOperator,
//             poolFee,
//             stakeAmount,
//             investor1
//         );


//         uint256 oldPoolID = pool.id();
//         uint256 newPoolID = pool2.id();
//         Account memory oldAccount;
//         Account memory newAccount;

//         uint256 borrowAmount = 0.5e18;

//         SignedCredential memory sc = issueGenericSC(address(agent));
//         agentBorrow(agent, borrowAmount, sc, pool, powerToken, sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//         oldAccount = AccountHelpers.getAccount(router, address(agent), oldPoolID);
//         assertEq(oldAccount.totalBorrowed, borrowAmount);
//         vm.startPrank(minerOwner);
//         agent.refinance(oldPoolID, newPoolID, 0, issueGenericSC(address(agent)));
//         oldAccount = AccountHelpers.getAccount(router, address(agent), oldPoolID);
//         newAccount = AccountHelpers.getAccount(router, address(agent), newPoolID);
//         assertEq(oldAccount.totalBorrowed, 0);
//         assertEq(newAccount.totalBorrowed, borrowAmount);
//         vm.stopPrank();
//     }
}

contract AgentPoliceTest is BaseTest {
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;

    address investor1 = makeAddr("INVESTOR_1");
    address minerOwner = makeAddr("MINER_OWNER");
    address administration = makeAddr("ADMINISTRATION");
    address liquidator = makeAddr("LIQUIDATOR");

    uint256 stakeAmount = 1000e18;

    IAgent agent;
    uint64 miner;
    IPool pool;
    IAgentPolice police;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
      police = GetRoute.agentPolice(router);
    }

    function testPutAgentOnAdministration(uint256 rollFwdPeriod, uint256 borrowAmount) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      borrowAmount = bound(borrowAmount, DUST, stakeAmount);
      // helper includes assertions
      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );
    }

    function testPutAgentOnAdministrationNoLoans() public {
      vm.startPrank(IAuth(address(police)).owner());
      try police.putAgentOnAdministration(address(agent), administration) {
        assertTrue(false, "Agent should not be eligible for administration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }
    }

    function testInvalidPutAgentOnAdministration() public {
      uint256 borrowAmount = 1e18;

      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      agentBorrow(agent, pool.id(), borrowCred);

      vm.startPrank(IAuth(address(police)).owner());
      try police.putAgentOnAdministration(address(agent), administration) {
        assertTrue(false, "Agent should not be eligible for administration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }
    }

    function testRmAgentFromAdministration() public {
      uint256 rollFwdPeriod = police.defaultWindow() + 100;
      uint256 borrowAmount = 1e18;

      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );

      // deal enough funds to the Agent so it can make a payment back to the Pool
      vm.deal(address(agent), borrowAmount * 2);

      SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

      // here we are exiting the pool by overpaying so much
      (,uint256 epochsPaid,) = agentPay(agent, pool, sc);

      require(epochsPaid == 0, "Should have exited from the pool");

      // check that the agent is no longer on administration
      vm.startPrank(IAuth(address(police)).owner());

      police.rmAgentFromAdministration(address(agent));

      assertEq(agent.administration(), address(0), "Agent Should not be on administration after paying up");
    }

    function testSetAgentDefaulted(uint256 rollFwdPeriod, uint256 borrowAmount) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      borrowAmount = bound(borrowAmount, DUST, stakeAmount);
      // helper includes assertions
      setAgentDefaulted(
        agent,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );
    }

    function testSetAdministrationNonAgentPolice(uint256 rollFwdPeriod) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      uint256 borrowAmount = 1e18;
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      agentBorrow(agent, pool.id(), borrowCred);

      vm.roll(block.number + rollFwdPeriod);

      try police.putAgentOnAdministration(address(agent), administration) {
        assertTrue(false, "only agent police owner should be able to call putAgentOnAdministration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }

      try agent.setAdministration(administration) {
        assertTrue(false, "only agent police should be able to put the agent on adminstration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }
    }

    function testRmAdministrationNonAgentPolice(uint256 rollFwdPeriod) public {
      uint256 rollFwdPeriod = police.defaultWindow() + 100;
      uint256 borrowAmount = 1e18;

      putAgentOnAdministration(
        agent,
        administration,
        rollFwdPeriod,
        borrowAmount,
        pool.id()
      );

      // deal enough funds to the Agent so it can make a payment back to the Pool
      vm.deal(address(agent), borrowAmount * 2);

      SignedCredential memory sc = issueGenericPayCred(agent.id(), address(agent).balance);

      // here we are exiting the pool by overpaying so much
      (,uint256 epochsPaid,) = agentPay(agent, pool, sc);

      require(epochsPaid == 0, "Should have exited from the pool");

      try police.rmAgentFromAdministration(address(agent)) {
        assertTrue(false, "only agent police owner operator should be able to call rmAgentFromAdministration");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }
    }

    function testSetAgentDefaultedNonAgentPolice(uint256 rollFwdPeriod) public {
      rollFwdPeriod = bound(
        rollFwdPeriod,
        police.defaultWindow() + 1,
        police.defaultWindow() * 10
      );

      uint256 borrowAmount = 1e18;
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);
      agentBorrow(agent, pool.id(), borrowCred);

      vm.roll(block.number + rollFwdPeriod);

      try police.setAgentDefaulted(address(agent)) {
        assertTrue(false, "only agent police owner operator should be able to call setAgentInDefault");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }

      try agent.setInDefault() {
        assertTrue(false, "only agent police should be able to call setAgentInDefault on the agent");
      } catch (bytes memory e) {
        assertEq(errorSelector(e), AgentPolice.Unauthorized.selector);
      }
    }
}

// contract AgentDefaultTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address investor2 = makeAddr("INVESTOR_2");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");
//     string poolName = "FIRST POOL NAME";
//     uint256 baseInterestRate = 20e18;
//     uint256 stakeAmount;

//     IAgent agent;
//     uint64 miner;
//     IPool pool1;
//     IPool pool2;
//     IERC4626 pool46261;
//     IERC4626 pool46262;

//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;

//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);

//         pool1 = createPool(
//             "TEST1",
//             "TEST1",
//             poolOperator,
//             2e18
//         );
//         pool46261 = IERC4626(address(pool1));

//         pool2 = createPool(
//             "TEST2",
//             "TEST2",
//             poolOperator,
//             2e18
//         );
//         pool46262 = IERC4626(address(pool2));
//         // investor1 stakes 10 FIL
//         vm.deal(investor1, 11e18);
//         stakeAmount = 5e18;
//         vm.startPrank(investor1);
//         wFIL.deposit{value: stakeAmount*2}();
//         wFIL.approve(address(pool1), stakeAmount);
//         wFIL.approve(address(pool2), stakeAmount);
//         pool46261.deposit(stakeAmount, investor1);
//         pool46262.deposit(stakeAmount, investor1);
//         vm.stopPrank();

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//         signedCred = issueGenericSC(address(agent));
//         agent.borrow(stakeAmount / 2, pool1.id(), signedCred, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         signedCred = issueGenericSC(address(agent));
//         agent.borrow(stakeAmount / 2, pool2.id(), signedCred, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         vm.stopPrank();
//     }

//     function testCheckOverLeveraged() public {
//         // 0 expected daily rewards
//         SignedCredential memory sc = issueSC(createCustomCredential(address(agent), 5e18, 0, 5e18, 4e18));

//         police.checkLeverage(address(agent), sc);

//         assertTrue(police.isOverLeveraged(address(agent)), "Agent should be over leveraged");
//     }

//     // in this test, we check default
//     // resulting in pools borrowAmounts being written down by the power token weighted agent liquidation value
//     function testCheckDefault() public {
//         // this credential gives a 1e18 liquidation value, and overleverage / overpowered
//         SignedCredential memory sc = issueSC(createCustomCredential(address(agent), 5e18, 0, 5e18, 4e18));

//         police.checkDefault(address(agent), sc);

//         assertTrue(police.isOverLeveraged(address(agent)), "Agent should be over leveraged");
//         assertTrue(police.isOverPowered(address(agent)), "Agent should be over powered");
//         assertTrue(police.isInDefault(address(agent)), "Agent should be in default");
//         uint256 pool1PostDefaultTotalBorrowed = pool1.totalBorrowed();
//         uint256 pool2PostDefaultTotalBorrowed = pool2.totalBorrowed();

//         // since _total_ MLV is 1e18, each pool should be be left with 1e18/2
//         assertEq(pool1PostDefaultTotalBorrowed, 1e18 / 2, "Wrong write down amount");
//         assertEq(pool2PostDefaultTotalBorrowed, 1e18 / 2, "Wrong write down amount");
//     }

// contract AgentCollateralsTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address investor2 = makeAddr("INVESTOR_2");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");
//     string poolName = "FIRST POOL NAME";
//     uint256 baseInterestRate = 20e18;
//     uint256 stakeAmount;

//     IAgent agent;
//     uint64 miner;
//     IPool pool1;
//     IPool pool2;
//     IERC4626 pool46261;
//     IERC4626 pool46262;

//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;

//     uint256 borrowAmount = 10e18;

//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);

//         pool1 = createPool(
//             "TEST1",
//             "TEST1",
//             poolOperator,
//             2e18
//         );
//         pool46261 = IERC4626(address(pool1));

//         pool2 = createPool(
//             "TEST2",
//             "TEST2",
//             poolOperator,
//             2e18
//         );
//         pool46262 = IERC4626(address(pool2));
//         // investor1 stakes 10 FIL
//         vm.deal(investor1, 50e18);
//         stakeAmount = 20e18;
//         vm.startPrank(investor1);
//         wFIL.deposit{value: stakeAmount*2}();
//         wFIL.approve(address(pool1), stakeAmount);
//         wFIL.approve(address(pool2), stakeAmount);
//         pool46261.deposit(stakeAmount, investor1);
//         pool46262.deposit(stakeAmount, investor1);
//         vm.stopPrank();

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);

//         SignedCredential memory sc = issueGenericSC(address(agent));
//         agent.borrow(borrowAmount, pool1.id(), sc, sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         sc = issueGenericSC(address(agent));
//         agent.borrow(borrowAmount, pool2.id(), sc, sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / 2);
//         vm.stopPrank();
//     }

//     function testGetMaxWithdrawUnderLiquidity() public {
//         /*
//             issue a new signed cred to make Agent's financial situation look like this:
//             - qap: 10e18
//             - pool 1 borrow amount 10e18
//             - pool 2 borrow amount 10e18
//             - pool1 power token stake 5e18
//             - pool2 power token stake 5e18
//             - agent assets: 10e18
//             - agent liabilities: 8e18
//             - agent liquid balance: 10e18
//             the agent should be able to withdraw:
//             liquid balance + assets - liabilities - minCollateralValuePool1 - minCollateralValuePool2
//             (both pools require 10% of their totalBorrwed amount)
//         */

//         SignedCredential memory sc = issueSC(createCustomCredential(
//             address(agent),
//             signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             signedCred.vc.getExpectedDailyRewards(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             signedCred.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             8e18
//         ));

//         // expected withdraw amount is the agents liquidation value minus the min collateral of both pools
//         uint256 liquidationValue = agent.liquidAssets() + sc.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - sc.vc.getLiabilities(IRouter(router).getRoute(ROUTE_CRED_PARSER));
//         // the mock pool implementation returns 10% of totalBorrowed for minCollateral
//         Account memory account1 = AccountHelpers.getAccount(router, address(agent), pool1.id());
//         Account memory account2 = AccountHelpers.getAccount(router, address(agent), pool2.id());

//         uint256 minCollateralPool1 = pool1.implementation().minCollateral(account1, sc.vc);
//         uint256 minCollateralPool2 = pool2.implementation().minCollateral(account2, sc.vc);
//         uint256 expectedWithdrawAmount = liquidationValue - minCollateralPool1 - minCollateralPool2;

//         uint256 withdrawAmount = agent.maxWithdraw(sc);
//         assertEq(withdrawAmount, expectedWithdrawAmount, "Wrong withdraw amount");
//     }

//     function testWithdrawUnderMax(uint256 withdrawAmount) public {
//         vm.assume(withdrawAmount < agent.maxWithdraw(signedCred));

//         address receiver = makeAddr("RECEIVER");

//         assertEq(receiver.balance, 0, "Receiver should have no balance");
//         vm.startPrank(minerOwner);
//         agent.withdrawBalance(receiver, withdrawAmount, issueGenericSC(address(agent)));
//         vm.stopPrank();
//         assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
//     }

//     function testWithdrawMax() public {
//         uint256 withdrawAmount = agent.maxWithdraw(signedCred);

//         address receiver = makeAddr("RECEIVER");

//         assertEq(receiver.balance, 0, "Receiver should have no balance");
//         vm.startPrank(minerOwner);
//         agent.withdrawBalance(receiver, withdrawAmount, issueGenericSC(address(agent)));
//         assertEq(receiver.balance, withdrawAmount, "Wrong withdraw amount");
//         vm.stopPrank();
//     }

//     function testWithdrawTooMuch(uint256 overWithdrawAmt) public {
//         address receiver = makeAddr("RECEIVER");
//         uint256 withdrawAmount = agent.maxWithdraw(signedCred);
//         vm.assume(overWithdrawAmt > withdrawAmount);
//         vm.startPrank(minerOwner);
//         try agent.withdrawBalance(receiver, withdrawAmount * 2, issueGenericSC(address(agent))) {
//             assertTrue(false, "Should not be able to withdraw more than the maxwithdraw amount");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }
//         vm.stopPrank();
//     }

//     function testMaxWithdrawToLiquidityLimit() public {
//         uint256 LIQUID_AMOUNT = 10000;
//         uint64[] memory _miners = new uint64[](1);
//         uint256[] memory _amounts = new uint256[](1);
//         // push funds to the miner so that the agent's liquid balance is less than the withdrawAmount
//         _amounts[0] = agent.liquidAssets() - LIQUID_AMOUNT;
//         _miners[0] = uint64(miner);
//         vm.startPrank(minerOwner);
//         agent.pushFundsToMiners(_miners, _amounts, issueGenericSC(address(agent)));

//         uint256 withdrawAmount = agent.maxWithdraw(issueGenericSC(address(agent)));

//         assertEq(withdrawAmount, LIQUID_AMOUNT, "max withdraw should be the liquidity limit");
//         vm.stopPrank();
//     }

//     function testRemoveMiner() public {
//         assertEq(agent.minersCount(), 1, "Agent should have 1 miner");
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));
//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // in this example, remove a miner that has no power or assets
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             0,
//             0,
//             0,
//             0
//         ));

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         assertEq(agent.minersCount(), 2, "Agent should have 2 miners");
//         assertEq(agent.miners(1), newMiner, "Miner should be added to the agent");
//         vm.startPrank(minerOwner);
//         agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred);
//         assertEq(agent.hasMiner(newMiner), false, "Miner should be removed");
//         vm.stopPrank();
//     }

//     function testRemoveMinerWithTooMuchPower(uint256 powerAmount) public {
//         vm.assume(powerAmount <= signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));

//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // in this example, remove a miner that contributes all the borrowing power
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             0,
//             0,
//             0
//         ));

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         vm.startPrank(minerOwner);
//         // TODO: replace with proper expect revert
//         try agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred) {
//             assertTrue(false, "Should not be able to remove a miner with too much power");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }
//     }

//     function testRemoveMinerWithTooLargeLiquidationValue() public {
//         uint64 newMiner = _newMiner(minerOwner);
//         address newMinerAddr = address(uint160(newMiner));
//         // add another miner to the agent
//         _agentClaimOwnership(address(agent), newMiner, minerOwner);

//         // transfer out the balance of the agent to reduce the total collateral of the agent
//         address recipient = makeAddr("RECIPIENT");
//         uint256 withdrawAmount = agent.maxWithdraw(issueGenericSC(address(agent)));
//         vm.startPrank(minerOwner);
//         agent.withdrawBalance(recipient, withdrawAmount, issueGenericSC(address(agent)));

//         // in this example, remove a miner that contributes all the assets
//         SignedCredential memory minerCred = issueSC(createCustomCredential(
//             newMinerAddr,
//             0,
//             0,
//             signedCred.vc.getAssets(IRouter(router).getRoute(ROUTE_CRED_PARSER)),
//             0
//         ));
//         vm.stopPrank();

//         address newMinerOwner = makeAddr("NEW_MINER_OWNER");

//         assertEq(agent.hasMiner(newMiner), true, "Agent should have miner before removing");
//         vm.startPrank(minerOwner);

//         try agent.removeMiner(newMinerOwner, newMiner, issueGenericSC(address(agent)), minerCred) {
//             assertTrue(false, "Should not be able to remove a miner with too much liquidation value");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), InsufficientCollateral.selector);
//         }

//         vm.stopPrank();
//     }
// }

// contract AgentTooManyPoolsTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");

//     IAgent agent;
//     uint64 miner;

//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;

//     uint256 stakeAmountPerPool = 2e18;
//     uint256 borrowAmountPerPool = 1e18;
//     uint256 maxPools;
//     uint256 powerTokenStakePerPool;

//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
//         // investor1 stakes 10 FIL
//         vm.deal(investor1, 50e18);
//         vm.prank(investor1);
//         wFIL.deposit{value: 50e18}();

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//         vm.stopPrank();
//         maxPools = GetRoute.agentPolice(router).maxPoolsPerAgent();
//         powerTokenStakePerPool = signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / (maxPools * 2);

//         for (uint256 i = 0; i <= maxPools; i++) {
//             string memory poolName = Strings.toString(i);
//             IPool _pool = createPool(
//                 poolName,
//                 poolName,
//                 poolOperator,
//                 2e18
//             );

//             _deposit(_pool);

//             vm.startPrank(minerOwner);
//             agent.borrow(
//                 borrowAmountPerPool,
//                 _pool.id(),
//                 issueGenericSC(address(agent)),
//                 powerTokenStakePerPool
//             );
//             vm.stopPrank();
//         }
//     }

//     function testTooManyPoolsBorrow() public {
//         // create maxPool + 1 pool
//         IPool pool = createPool(
//             "Too manyith pool",
//             "OOPS",
//             poolOperator,
//             2e18
//         );

//         _deposit(pool);

//         vm.startPrank(minerOwner);
//         try agent.borrow(
//             borrowAmountPerPool,
//             pool.id(),
//             issueGenericSC(address(agent)),
//             powerTokenStakePerPool
//         ) {
//             assertTrue(false, "Agent should not be able to borrow from 11 pools");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), BadAgentState.selector);
//         }
//         vm.stopPrank();
//     }

//     function _deposit(IPool pool) internal {
//         vm.startPrank(investor1);
//         wFIL.approve(address(pool), stakeAmountPerPool);
//         pool.deposit(stakeAmountPerPool, investor1);
//         vm.stopPrank();
//     }
// }
