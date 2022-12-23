// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "./BaseTest.sol";
import {PowerToken} from "src/PowerToken/PowerToken.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {VerifiableCredential, MinerData} from "src/Types/Structs/Credentials.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract PowerTokenTest is BaseTest {
  IPool pool;
  VerifiableCredential public vc;
  IAgent agent;
  address public agentOwner;
  uint8 public v;
  bytes32 public r;
  bytes32 public s;
  PowerToken public powerToken;
  IPoolFactory public poolFactory;

  function setUp() public {
    agentOwner = makeAddr("OWNER");
    powerToken = PowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));

    (agent,) = configureAgent(agentOwner);

    (vc, v, r, s) = issueGenericVC(address(agent));

    pool = poolFactory.createPool(
        "TEST",
        "TEST",
        ZERO_ADDRESS,
        ZERO_ADDRESS
    );
  }

  function testMintBurnPower() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);
    uint256 bal = powerToken.balanceOf(address(agent));
    assertEq(bal, vc.miner.qaPower, "agent should have 10e18 power tokens");

    // issue new vc at newer block
    vm.roll(block.number + 1);
    (vc, v, r, s) = issueGenericVC(address(agent));
    vm.prank(agentOwner);
    agent.burnPower(vc.miner.qaPower, vc, v, r, s);

    bal = powerToken.balanceOf(address(agent));
    assertEq(bal, 0, "agent should have 0 power tokens");
  }

  function testTransferFromAgentPool() public {
    uint256 stakeAmount = vc.miner.qaPower - 100;
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    vm.prank(address(pool));
    powerToken.transferFrom(address(agent), address(pool), stakeAmount);
    uint256 poolBal = powerToken.balanceOf(address(pool));
    assertEq(poolBal, stakeAmount, "pool wrong power token balance");
  }

  function testMintTooMuchPower() public {
    vm.prank(agentOwner);
    vm.expectRevert("Cannot mint more power than the miner has");
    agent.mintPower(vc.miner.qaPower + 1, vc, v, r, s);
  }

  function testNonAgentMint() public {
    vm.expectRevert("PowerToken: Not authorized");
    powerToken.mint(1e18);
  }

  function testAgentOwnerNoMint() public {
    vm.expectRevert("PowerToken: Not authorized");
    vm.prank(agentOwner);
    powerToken.mint(1e18);
  }

  function testTransferAgentPool() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.miner.qaPower - 100, "agent should have 10e18 - 100 power tokens");
    assertEq(powerToken.balanceOf(address(pool)), 100, "pool should have 100 power tokens");
  }

  function testTransferPoolNonAgent() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.expectRevert("PowerToken: Pool can only transfer power tokens to agents");
    vm.prank(address(pool));
    powerToken.transfer(makeAddr("RECIPIENT"), 100);
  }

  function testTransferPoolAgent() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.prank(address(pool));
    powerToken.transfer(address(agent), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.miner.qaPower, "agent has wrong balanceof power tokens");
  }

  function testAgentApprovePool() public {
    uint256 stakeAmount = 1e18;
    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    uint256 allowance = powerToken.allowance(address(agent), address(pool));
    assertEq(allowance, stakeAmount, "pool should have non 0 allowance");
  }

  function testTransferFromNonAgentPool() public {
    vm.expectRevert("PowerToken: Invalid transfer");
    vm.prank(address(pool));
    powerToken.transferFrom(makeAddr("TEST"), address(pool), 0);
  }

  function testTransferFromAgentNonPool() public {
    vm.expectRevert("PowerToken: Agent can only transfer power tokens to pools");
    vm.prank(address(agent));
    powerToken.transferFrom(address(agent), makeAddr("TEST"), 0);
  }

  function testTransferFromPoolNonAgent() public {
    vm.expectRevert("PowerToken: Pool can only transfer power tokens to agents");
    address testAddr = makeAddr("TEST");
    vm.prank(testAddr);
    powerToken.transferFrom(address(pool), testAddr, 0);
  }

  function testSafeTransferFromAgentPool() public {
    uint256 stakeAmount = vc.miner.qaPower - 100;
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.approve(address(pool), stakeAmount);

    vm.prank(address(pool));
    SafeTransferLib.safeTransferFrom(ERC20(powerToken), address(agent), address(pool), stakeAmount);
    uint256 poolBal = powerToken.balanceOf(address(pool));
    assertEq(poolBal, stakeAmount, "pool wrong power token balance");
  }

  function testSafeTransferAgentPool() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    SafeTransferLib.safeTransfer(ERC20(powerToken), address(pool), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.miner.qaPower - 100, "agent should have 10e18 - 100 power tokens");
    assertEq(powerToken.balanceOf(address(pool)), 100, "pool should have 100 power tokens");
  }

  // for some reason vm.expectRevert("TRANSFER_FAILED") and vm.expectRevert("PowerToken: Pool can only transfer power tokens to agents") don't work here
  function testFailSafeTransferPoolNonAgent() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    // vm.expectRevert("TRANSFER_FAILED");
    vm.prank(address(pool));
    SafeTransferLib.safeTransfer(ERC20(powerToken), makeAddr("RECIPIENT"), 100);
  }

  function testSafeTransferPoolAgent() public {
    vm.prank(agentOwner);
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.prank(address(agent));
    powerToken.transfer(address(pool), 100);

    vm.prank(address(pool));
    SafeTransferLib.safeTransfer(ERC20(powerToken), address(agent), 100);

    assertEq(powerToken.balanceOf(address(agent)), vc.miner.qaPower, "agent has wrong balanceof power tokens");
  }

  function testAgentSafeApprovePool() public {
    uint256 stakeAmount = 1e18;
    vm.prank(address(agent));
    SafeTransferLib.safeApprove(ERC20(powerToken), address(pool), stakeAmount);

    uint256 allowance = powerToken.allowance(address(agent), address(pool));
    assertEq(allowance, stakeAmount, "pool should have non 0 allowance");
  }

  // for some reason vm.expectRevert("...") doesn't work here
  function testFailSafeTransferFromNonAgentPool() public {
    // vm.expectRevert("TRANSFER_FROM_FAILED");
    vm.prank(address(pool));
    SafeTransferLib.safeTransferFrom(ERC20(powerToken), makeAddr("TEST"), address(pool), 0);
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
    vm.expectRevert("PowerToken: Not authorized");
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
    vm.expectRevert("PowerToken: Contract is paused");
    agent.mintPower(vc.miner.qaPower, vc, v, r, s);

    vm.stopPrank();
  }
}
