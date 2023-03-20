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
          assertEq(errorSelector(e), MinerRegistry.DuplicateEntry.selector);
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

    //     function testSingleUseCredentials() public {
//         uint256 borrowAmount = 0.5e18;
//         vm.roll(block.number + 1);
//         uint256 borrowBlock = block.number;
//         vm.startPrank(minerOwner);
//         SignedCredential memory sc = issueGenericSC(address(agent));
//         uint256 qaPower = sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER));
//         agent.borrow(borrowAmount / 3, 0, sc, qaPower / 3);
//         vm.expectRevert(abi.encodeWithSelector(InvalidCredential.selector));
//         agent.borrow(borrowAmount / 3, 0, sc, qaPower / 3);
//         vm.stopPrank();
//     }
}

contract AgentWithdrawTest is BaseTest {

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

    function testPushFundsToMiners(uint256 pushAmount) public {
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
      vm.assume(borrowAmount <= stakeAmount);
      SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

      vm.startPrank(minerOwner);
      uint256 borrowBlock = block.number;
      agent.borrow(pool.id(), borrowCred);
      vm.stopPrank();

      Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());
      assertEq(account.principal, borrowAmount);
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

contract AgentTest is BaseTest {
    using Credentials for VerifiableCredential;
    using AccountHelpers for Account;
    address investor1 = makeAddr("INVESTOR_1");
//     address investor2 = makeAddr("INVESTOR_2");
    address minerOwner = makeAddr("MINER_OWNER");
//     uint256 borrowAmount = 0.5e18;
    uint256 stakeAmount = 1000e18;
//     uint256 poolFee = 2e18;

    IAgent agent;
    uint64 miner;
    IPool pool;

    function setUp() public {
      pool = createAndFundPool(stakeAmount, investor1);
      (agent, miner) = configureAgent(minerOwner);
    }

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

//     function testSingleUseCredentials() public {
//         uint256 borrowAmount = 0.5e18;
//         vm.roll(block.number + 1);
//         uint256 borrowBlock = block.number;
//         vm.startPrank(minerOwner);
//         SignedCredential memory sc = issueGenericSC(address(agent));
//         uint256 qaPower = sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER));
//         agent.borrow(borrowAmount / 3, 0, sc, qaPower / 3);
//         vm.expectRevert(abi.encodeWithSelector(InvalidCredential.selector));
//         agent.borrow(borrowAmount / 3, 0, sc, qaPower / 3);
//         vm.stopPrank();
//     }
}

// contract AgentPoliceTest is BaseTest {
//     using AccountHelpers for Account;
//     using Credentials for VerifiableCredential;

//     address investor1 = makeAddr("INVESTOR_1");
//     address investor2 = makeAddr("INVESTOR_2");
//     address minerOwner = makeAddr("MINER_OWNER");
//     address poolOperator = makeAddr("POOL_OPERATOR");
//     string poolName = "FIRST POOL NAME";
//     uint256 baseInterestRate = 20e18;
//     uint256 poolFee = 2e18;
//     uint256 stakeAmount = 10e18;

//     IAgent agent;
//     uint64 miner;
//     IPool pool;
//     IERC4626 pool4626;
//     SignedCredential signedCred;
//     IAgentPolice police;

//     address powerToken;


//     function setUp() public {
//         police = GetRoute.agentPolice(router);
//         powerToken = IRouter(router).getRoute(ROUTE_POWER_TOKEN);
//         pool = createAndPrimePool(
//             "TEST",
//             "TEST",
//             poolOperator,
//             poolFee,
//             stakeAmount,
//             investor1
//         );

//         (agent, miner) = configureAgent(minerOwner);
//         // mint some power for the agent
//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(_agentOperator(agent));
//         agent.mintPower(signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), signedCred);
//         vm.stopPrank();
//     }

//     function testNextPmtWindowDeadline() public {
//         vm.roll(0);
//         uint256 windowLength = police.windowLength();
//         uint256 nextPmtWindowDeadline = police.nextPmtWindowDeadline();
//         // first window's deadline is the windowLength
//         assertEq(nextPmtWindowDeadline, windowLength);

//         vm.roll(block.number + windowLength + 10);
//         nextPmtWindowDeadline = police.nextPmtWindowDeadline();
//         assertEq(nextPmtWindowDeadline, windowLength * 2);
//     }

//     function testCheckOverPowered() public {
//         uint256 powerTokenStake = 7.5e18;
//         uint256 borrowAmount = 1e18;
//         uint256 newQAPower = 5e18;
//         SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

//         // since agent has not staked any power tokens, the checkPower function should burn the tokens to the correct power amount
//         police.checkPower(address(agent), sc);

//         assertTrue(police.isOverPowered(address(agent)));
//         assertTrue(police.isOverPowered(agent.id()));
//         assertEq(
//             IERC20(powerToken).balanceOf(address(agent)),
//             signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - powerTokenStake
//         );
//     }

//     function testBorrowWhenOverPowered() public {
//         uint256 borrowAmount = 0.5e18;
//         uint256 powerTokenStake = 7.5e18;
//         uint256 newQAPower = 5e18;
//         SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

//         vm.startPrank(minerOwner);
//         try agent.borrow(borrowAmount, 0, sc, powerTokenStake) {
//             assertTrue(false, "Call to borrow shoudl err when over pwered");
//         } catch (bytes memory err) {
//             assertEq(errorSelector(err), BadAgentState.selector);
//         }
//     }

//     function testRecoverOverPoweredByBurn() public {
//         uint256 borrowAmount = 0.5e18;
//         uint256 powerTokenStake = 7.5e18;
//         uint256 newQAPower = 7.5e18;
//         SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

//         vm.startPrank(minerOwner);
//         agent.exit(pool.id(), borrowAmount, sc);
//         sc = issueOverPoweredCred(address(agent), newQAPower);
//         agent.burnPower(2.5e18, sc);
//         vm.stopPrank();
//         sc = issueOverPoweredCred(address(agent), newQAPower);
//         police.checkPower(address(agent), sc);

//         assertEq(IERC20(address(powerToken)).totalSupply(), 7.5e18);
//         assertEq(police.isOverPowered(address(agent)), false);
//     }

//     function testRecoverOverPoweredStateIncreasePower() public {
//         uint256 borrowAmount = 0.5e18;
//         uint256 powerTokenStake = 7.5e18;
//         uint256 newQAPower = 5e18;
//         makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);
//         SignedCredential memory sc = issueGenericSC(address(agent));

//         police.checkPower(address(agent), sc);

//         // no power was burned
//         assertEq(IERC20(address(powerToken)).totalSupply(), signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//         assertEq(police.isOverPowered(address(agent)), false);    }

//     function testRemoveMinerWhenOverPowered() public {
//         uint256 borrowAmount = 0.5e18;
//         uint256 powerTokenStake = 7.5e18;
//         uint256 newQAPower = 5e18;
//         makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

//         signedCred = issueGenericSC(address(agent));
//         vm.startPrank(minerOwner);
//         try agent.removeMiner(address(this), miner, signedCred, signedCred) {
//             assertTrue(false, "Call to borrow shoudl err when over pwered");
//         } catch (bytes memory err) {
//             assertEq(errorSelector(err), BadAgentState.selector);
//         }
//     }

//     function testForceBurnPowerWhenNotOverPowered() public {
//         signedCred = issueGenericSC(address(agent));
//         try police.forceBurnPower(address(agent), signedCred) {
//             assertTrue(false, "Call to borrow shoudl err when over pwered");
//         } catch (bytes memory err) {
//             (, string memory reason) = Decode.notOverPoweredError(err);
//             assertEq(reason, "AgentPolice: Agent is not overpowered");
//         }
//     }

//     // agent does not end up overpowered because the agent has enough power tokens liquid to cover the decrease in real power
//     function testForceBurnPowerWithAdequateBal() public {
//         uint256 newQAPower = 5e18;

//         AgentData memory AgentData = AgentData(
//             1e10, 20e18, 0.5e18, 10e18, 10e18, 0, 10, newQAPower, 5e18, 0, 0
//         );

//         VerifiableCredential memory _vc = VerifiableCredential(
//             vcIssuer,
//             address(agent),
//             block.number,
//             block.number + 100,
//             1000,
//             abi.encode(AgentData)
//         );

//         SignedCredential memory sc = issueSC(_vc);
//         police.checkPower(address(agent), sc);
//         assertTrue(police.isOverPowered(address(agent)), "Agent should be overed powered");
//         police.forceBurnPower(address(agent), sc);

//         assertEq(IPowerToken(powerToken).powerTokensMinted(agent.id()), sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), "Agent should have 5e18 power tokens minted");
//         assertEq(IERC20(address(powerToken)).totalSupply(), 5e18);
//         assertEq(police.isOverPowered(address(agent)), false);
//     }

//     function testForceBurnPowerWithInadequateBal() public {
//         uint256 borrowAmount = 0.5e18;
//         uint256 powerTokenStake = 7.5e18;
//         uint256 newQAPower = 5e18;
//         SignedCredential memory sc = makeAgentOverPowered(powerTokenStake, borrowAmount, newQAPower);

//         assertTrue(IERC20(address(powerToken)).balanceOf(address(agent)) == 2.5e18, "agent should have 2.5e18 power tokens");

//         police.checkPower(address(agent), sc);
//         sc = issueOverPoweredCred(address(agent), newQAPower);
//         police.forceBurnPower(address(agent), sc);
//         // 2.5e18 tokens should get burned because thats the balance of the agent's power tokens
//         assertTrue(IERC20(address(powerToken)).totalSupply() == 7.5e18, "total supply should be 7.5e18");
//         assertTrue(IERC20(address(powerToken)).balanceOf(address(pool)) == powerTokenStake, "agent should have 0 power tokens");
//         assertTrue(IERC20(address(powerToken)).balanceOf(address(agent)) == 0, "agent should have 0 power tokens");
//         assertTrue(police.isOverPowered(address(agent)), "agent should be overpowered");
//     }

//     function testForcePullFundsFromMinersWhenNotOverleveraged() public {
//         // prepare a second miner to draw funds from
//         uint64 secondMiner = configureMiner(address(agent), minerOwner);

//         address miner1 = idStore.ids(miner);
//         address miner2 = idStore.ids(secondMiner);

//         // give the miners some funds to pull
//         vm.deal(miner1, 1e18);
//         vm.deal(miner2, 2e18);


//         assertEq(wFIL.balanceOf(address(agent)), 0);

//         // create calldata for pullFundsFromMiners
//         uint64[] memory _miners = new uint64[](2);
//         _miners[0] = miner;
//         _miners[1] = secondMiner;

//         vm.startPrank(IAuth(address(police)).owner());
//         // TODO: replace with proper expect revert

//         try police.forcePullFundsFromMiners(address(agent), _miners, new uint256[](2), issueGenericSC(address(agent))) {
//             assertTrue(false, "Call to borrow shoudl err when over pwered");
//         } catch (bytes memory err) {
//             (, string memory reason) = Decode.notOverLeveragedError(err);
//             assertEq(reason, "AgentPolice: Agent is not overleveraged");
//         }

//         vm.stopPrank();
//     }

//     function testForcePullFundsFromMiners() public {
//         // TODO: Look over the logic of this test
//         makeAgentOverLeveraged(1e18, 1e18);

//         uint64 secondMiner = configureMiner(address(agent), minerOwner);
//         address miner1 = idStore.ids(miner);
//         address miner2 = idStore.ids(secondMiner);
//         // give the miners some funds to pull
//         uint256 FUND_AMOUNT = 50e18;
//         vm.deal(miner1, FUND_AMOUNT);
//         vm.deal(miner2, FUND_AMOUNT);

//         uint256 agentBalance = wFIL.balanceOf(address(agent));
//         // empty out agent wallet for testing
//         vm.prank(address(agent));
//         wFIL.transfer(minerOwner, agentBalance);
//         // assertEq(wFIL20.balanceOf(address(agent)), 0);

//         // create calldata for pullFundsFromMiners
//         uint64[] memory _miners = new uint64[](2);
//         _miners[0] = miner;
//         _miners[1] = secondMiner;

//         uint256 FORCE_PULL_AMNT = 10e18;
//         uint256[] memory _amounts = new uint256[](2);
//         _amounts[0] = FORCE_PULL_AMNT;
//         _amounts[1] = FORCE_PULL_AMNT;

//         assertEq(address(agent).balance, 0, "agent should have no FIL");

//         vm.startPrank(IAuth(address(police)).owner());
//         police.forcePullFundsFromMiners(address(agent), _miners, _amounts, issueGenericSC(address(agent)));

//         assertEq(address(agent).balance, FORCE_PULL_AMNT * 2, "Agent should have 2 times the force pull amount of FIL");
//         vm.stopPrank();
//     }

//     function testForceMakePayments() public {
//         // give the agent enough funcds to get current
//         pushWFILFunds(address(agent), 100e18, makeAddr("FUNDER"));


//         SignedCredential memory signedCredential = makeAgentOverLeveraged(1e18, 1e18);
//         vm.startPrank(IAuth(address(police)).owner());
//         police.forceMakePayments(address(agent), signedCredential);
//         vm.stopPrank();
//         Account memory account = AccountHelpers.getAccount(router, agent.id(), pool.id());

//         assertEq(account.epochsPaid, police.windowInfo().deadline, "Agent should have paid up to current epoch");
//     }

//     function testSetWindowLengthNonAdmin() public {
//         uint256 newWindowPeriod = 100;
//         try police.setWindowLength(newWindowPeriod) {
//             assertTrue(false, "Should have reverted with Unauthorized error");
//         } catch (bytes memory err) {
//             assertEq(errorSelector(err), Unauthorized.selector);
//         }
//     }

//     function testSetWindowLength() public {
//         uint256 newWindowPeriod = 100;
//         vm.prank(IAuth(address(police)).owner());
//         police.setWindowLength(newWindowPeriod);
//         assertEq(police.windowLength(), newWindowPeriod);
//     }

//     function testTransferOwnershipNonAdmin() public {
//         try IAuth(address(police)).transferOwnership(address(this)) {
//             assertTrue(false, "Should not be able to transfer ownership");
//         } catch (bytes memory b) {
//             assertEq(errorSelector(b), Unauthorized.selector);
//         }
//     }

//     function testTransferOwnership() public {
//         address owner = IAuth(address(police)).owner();
//         address newOwner = makeAddr("NEW OWNER");

//         vm.prank(owner);
//         IAuth(address(police)).transferOwnership(newOwner);
//         vm.prank(newOwner);
//         IAuth(address(police)).acceptOwnership();

//         assertEq(IAuth(address(police)).owner(), newOwner);
//     }

//     function testTransferOperator() public {
//         address owner = IAuth(address(police)).owner();
//         address newOperator = makeAddr("NEW OPERATOR");

//         vm.prank(owner);
//         IAuth(address(police)).transferOperator(newOperator);
//         vm.prank(newOperator);
//         IAuth(address(police)).acceptOperator();

//         assertEq(IAuth(address(police)).operator(), newOperator);
//     }

//     function testLockoutNonAdmin() public {
//         try police.lockout(address(0), 0) {
//             assertTrue(false, "Should have reverted with Unauthorized error");
//         } catch (bytes memory err) {
//             assertEq(errorSelector(err), Unauthorized.selector);
//         }
//     }

//     function makeAgentOverPowered(uint256 powerTokenStake, uint256 borrowAmount, uint256 newQAPower) internal returns (
//         SignedCredential memory sc
//     ) {
//         agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, powerToken, powerTokenStake);
//         assertEq(wFIL.balanceOf(address(agent)), borrowAmount);
//         assertEq(IERC20(powerToken).balanceOf(address(pool)), powerTokenStake);
//         uint256 agentPowTokenBal = IERC20(powerToken).balanceOf(address(agent));
//         assertEq(agentPowTokenBal, signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - powerTokenStake);

//         sc = issueOverPoweredCred(address(agent), newQAPower);

//         // no funds get burned here
//         police.checkPower(address(agent), sc);

//         assertEq(IERC20(address(powerToken)).totalSupply(), signedCred.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)));
//         assertTrue(police.isOverPowered(address(agent)));
//         assertTrue(police.isOverPowered(agent.id()));
//     }

//     function issueOverPoweredCred(address agent, uint256 newQAPower) internal returns (SignedCredential memory) {
//         vm.roll(block.number + 1);
//         return issueSC(createCustomCredential(address(agent), newQAPower, 10e18, 5e18, 1e18));
//     }

//     function makeAgentOverLeveraged(uint256 borrowAmount, uint256 powerTokenStake) internal returns (
//         SignedCredential memory sc
//     ) {
//         agentBorrow(agent, borrowAmount, issueGenericSC(address(agent)), pool, powerToken, powerTokenStake);

//         sc = issueSC(createCustomCredential(
//             address(agent),
//             10e18,
//             // 0 expected daily rewards
//             0,
//             5e18,
//             0
//         ));

//         police.checkLeverage(address(agent), sc);

//         vm.roll(block.number + 1);
//         sc = issueSC(createCustomCredential(
//             address(agent),
//             10e18,
//             // 0 expected daily rewards
//             0,
//             5e18,
//             0
//         ));
//         assertTrue(police.isOverLeveraged(agent.id()));
//     }
// }

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
// }

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
