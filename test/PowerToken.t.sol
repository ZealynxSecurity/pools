// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseTest.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PowerToken} from "src/PowerToken/PowerToken.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {VerifiableCredential, AgentData} from "src/Types/Structs/Credentials.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Decode} from "src/Errors.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";

contract PowerTokenTest is BaseTest {
  using Credentials for VerifiableCredential;
  IPool pool;
  SignedCredential public sc;
  VerifiableCredential public vc;
  IAgent agent;
  address public agentOwner;
  PowerToken public powerToken;
  IPoolFactory public poolFactory;

  address poolOperator = makeAddr("POOL_OPERATOR");

  function setUp() public {
    agentOwner = makeAddr("OWNER");
    powerToken = PowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    poolFactory = GetRoute.poolFactory(router);

    (agent,) = configureAgent(agentOwner);

    sc = issueGenericSC(address(agent));
    vc = sc.vc;
    pool = createPool(
        "TEST",
        "TEST",
        poolOperator,
        0
    );
  }

  function testMintBurnPower() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    uint256 bal = powerToken.balanceOf(address(agent));
    assertEq(bal, vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), "agent should have 10e18 power tokens");

    // issue new vc at newer block
    vm.roll(block.number + 1);
    sc = issueGenericSC(address(agent));
    vm.startPrank(agentOwner);
    agent.burnPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    bal = powerToken.balanceOf(address(agent));
    assertEq(bal, 0, "agent should have 0 power tokens");
  }

  function testTransferFromAgentPool() public {
    uint256 stakeAmount = vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - 100;
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    vm.prank(address(pool));
    powerToken.transferFrom(address(agent), address(pool), stakeAmount);
    uint256 poolBal = powerToken.balanceOf(address(pool));
    assertEq(poolBal, stakeAmount, "pool wrong power token balance");
  }

  function testMintTooMuchPower() public {
    vm.startPrank(agentOwner);
    uint256 qa = vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER));
    vm.expectRevert("Cannot mint more power than the miner has");
    agent.mintPower(qa + 1, sc);
    vm.stopPrank();
  }

  function testNonAgentMint() public {
    vm.expectRevert("onlyAgent: Not authorized");
    powerToken.mint(1e18);
  }

  function testAgentOwnerNoMint() public {
    vm.expectRevert("onlyAgent: Not authorized");
    vm.prank(agentOwner);
    powerToken.mint(1e18);
  }

  function testTransferAgentPool() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - 100, "agent should have 10e18 - 100 power tokens");
    assertEq(powerToken.balanceOf(address(pool)), 100, "pool should have 100 power tokens");
  }

  function testTransferPoolNonAgent() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.prank(address(pool));
    try powerToken.transfer(makeAddr("RECIPIENT"), 100) {
        assertTrue(false, "testTransferPoolNonAgent should revert.");
    } catch (bytes memory e) {
      (
        address target,
        address caller,
        bytes4 funcSig,
        string memory reason
      ) = Decode.unauthorizedError(e);

      assertEq(target, address(powerToken), "target should be powerToken");
      assertEq(caller, address(pool), "caller should be pool");
      assertEq(funcSig, powerToken.transfer.selector, "funcSig should be transferFrom");
      assertEq(reason, "PowerToken: Invalid to address");
    }
  }

  function testTransferPoolAgent() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.prank(address(pool));
    powerToken.transfer(address(agent), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), "agent has wrong balanceof power tokens");
  }

  function testAgentApprovePool() public {
    uint256 stakeAmount = 1e18;
    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    uint256 allowance = powerToken.allowance(address(agent), address(pool));
    assertEq(allowance, stakeAmount, "pool should have non 0 allowance");
  }

  function testTransferFromAgentNonPool() public {
    vm.startPrank(address(agent));
    try powerToken.transferFrom(address(agent), makeAddr("TEST"), 0) {
        assertTrue(false, "transferFromAgentNonPool should revert.");
    } catch (bytes memory e) {
      (
        address target,
        address caller,
        bytes4 funcSig,
        string memory reason
      ) = Decode.unauthorizedError(e);

      assertEq(target, address(powerToken), "target should be powerToken");
      assertEq(caller, address(agent), "caller should be agent");
      assertEq(funcSig, powerToken.transferFrom.selector, "funcSig should be transferFrom");
      assertEq(reason, "PowerToken: Invalid to address");
    }
    vm.stopPrank();
  }

  function testTransferFromPoolNonAgent() public {
    vm.prank(address(agent));
    try powerToken.transferFrom(address(pool), makeAddr("testAddr"), 0) {
        assertTrue(false, "testTransferFromPoolNonAgent should revert.");
    } catch (bytes memory e) {
      (
        address target,
        address caller,
        bytes4 funcSig,
        string memory reason
      ) = Decode.unauthorizedError(e);

      assertEq(target, address(powerToken), "target should be powerToken");
      assertEq(caller, address(agent), "caller should be agent");
      assertEq(funcSig, powerToken.transferFrom.selector, "funcSig should be transferFrom");
      assertEq(reason, "PowerToken: Invalid to address");
    }
  }

  function testSafeTransferFromAgentPool() public {
    uint256 stakeAmount = vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - 100;
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();

    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    vm.prank(address(pool));
    SafeTransferLib.safeTransferFrom(ERC20(powerToken), address(agent), address(pool), stakeAmount);
    uint256 poolBal = powerToken.balanceOf(address(pool));
    assertEq(poolBal, stakeAmount, "pool wrong power token balance");
  }

  function testSafeTransferAgentPool() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    SafeTransferLib.safeTransfer(ERC20(powerToken), address(pool), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) - 100, "agent should have 10e18 - 100 power tokens");
    assertEq(powerToken.balanceOf(address(pool)), 100, "pool should have 100 power tokens");
  }

  // for some reason vm.expectRevert("TRANSFER_FAILED") and vm.expectRevert("PowerToken: Pool can only transfer power tokens to agents") don't work here
  function testFailSafeTransferPoolNonAgent() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    // vm.expectRevert("TRANSFER_FAILED");
    vm.prank(address(pool));
    SafeTransferLib.safeTransfer(ERC20(powerToken), makeAddr("RECIPIENT"), 100);
  }

  function testSafeTransferPoolAgent() public {
    vm.startPrank(agentOwner);
    agent.mintPower(vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), sc);
    vm.stopPrank();
    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.prank(address(pool));
    SafeTransferLib.safeTransfer(ERC20(powerToken), address(agent), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)), "agent has wrong balanceof power tokens");
  }

  function testAgentSafeApprovePool() public {
    uint256 stakeAmount = 1e18;
    vm.prank(address(agent));
    SafeTransferLib.safeApprove(ERC20(powerToken), address(pool), stakeAmount);

    uint256 allowance = powerToken.allowance(address(agent), address(pool));
    assertEq(allowance, stakeAmount, "pool should have non 0 allowance");
  }

  // for some reason vm.expectRevert("...") doesn't work here
  function testFailSafeTransferFromAgentNonPool() public {
    // vm.expectRevert("TRANSFER_FROM_FAILED");
    vm.prank(address(agent));
    SafeTransferLib.safeTransferFrom(ERC20(powerToken), address(agent), makeAddr("TEST"), 0);
  }

  // for some reason vm.expectRevert("...") doesn't work here
  function testFailSafeTransferFromPoolNonAgent() public {
    // vm.expectRevert("PowerToken: Pool can only transfer power tokens to agents");
    address testAddr = makeAddr("TEST");
    vm.prank(testAddr);
    SafeTransferLib.safeTransferFrom(ERC20(powerToken), address(pool), testAddr, 0);
  }

  function testPauseResume() public {
    address powerTokenAdmin = IRouter(router).getRoute(ROUTE_POWER_TOKEN_ADMIN);
    vm.startPrank(powerTokenAdmin);
    powerToken.pause();
    assertTrue(powerToken.paused(), "power token should be paused");

    powerToken.resume();
    assertTrue(!powerToken.paused(), "power token should not be paused");
    vm.stopPrank();
  }

  function testPauseNonAdmin() public {
    vm.expectRevert("requiresSubAuth: Not authorized");
    powerToken.pause();
  }

  function testFunctionalityPausedDuringPause() public {
    address powerTokenAdmin = IRouter(router).getRoute(ROUTE_POWER_TOKEN_ADMIN);

    vm.prank(powerTokenAdmin);
    powerToken.pause();

    vm.expectRevert("PowerToken: Contract is paused");
    vm.startPrank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.expectRevert("PowerToken: Contract is paused");
    powerToken.approve(address(pool), 100);

    vm.expectRevert("PowerToken: Contract is paused");
    powerToken.transferFrom(address(agent), address(pool), 100);

    vm.expectRevert("PowerToken: Contract is paused");
    powerToken.mint(100);

    vm.expectRevert("PowerToken: Contract is paused");
    powerToken.burn(100);

    vm.stopPrank();

    vm.startPrank(address(agent));
    uint256 qa = vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER));
    vm.expectRevert("PowerToken: Contract is paused");
    agent.mintPower(qa, sc);

    vm.stopPrank();
  }
}
