// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {PoolToken} from "shim/PoolToken.sol";
import {console} from "forge-std/console.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

import {BaseTest} from "./BaseTest.sol";

contract OffRampTest is BaseTest {
  IOffRamp ramp;
  PoolToken iou;
  IPool pool;
  address poolRegistry = makeAddr("POOLREGISTRY");

  address investor1 = makeAddr("INVESTOR1");
  address investor2 = makeAddr("INVESTOR2");
  address investor3 = makeAddr("INVESTOR3");
  address poolOperator = makeAddr("POOL_OPERATOR");
  uint256 conversionWindow;
  uint256 dust = 1000;
  uint256 maxSupply = 2000000000e18;
  uint256 EPOCHS_IN_20_YEARS = 20 * EPOCHS_IN_YEAR;
  function setUp() public {
    // mock the pool factory for offramp permissioning
    vm.prank(systemAdmin);

    vm.stopPrank();
    pool = createPool();
    ramp = _configureOffRamp(pool);
    conversionWindow = ramp.conversionWindow();
    iou = PoolToken(ramp.iouToken());
  }
  function testDistributeSimple(uint256 initialBalance, uint256 timeChunk) public {
    (initialBalance, timeChunk) = _loadAssumptions(initialBalance, timeChunk);
    _mintWFILToOfframp(initialBalance);
    (uint256 _toDistribute, uint256 _deltaBlocks, uint256 _buffer) = ramp.bufferInfo();
    assertEq(_buffer, initialBalance);
    assertEq(_toDistribute, 0);
    vm.roll(block.number + timeChunk);
    (_toDistribute, _deltaBlocks, _buffer) = ramp.bufferInfo();
    assertEq(initialBalance, _toDistribute);
    assertEq(wFIL.balanceOf(address(ramp)), initialBalance);
    (
      uint256 stakedIOUs,
      uint256 pendingDivs,
      uint256 realizeableIOUs,
      uint256 claimableIOUs
    ) = ramp.userInfo(investor1);
    assertEq(stakedIOUs, 0);
    assertEq(pendingDivs, 0);
    assertEq(realizeableIOUs, 0);
    assertEq(claimableIOUs, 0);
  }
  function testStakeSimple(uint256 initialBalance, uint256 timeChunk) public {
    (initialBalance, timeChunk) = _loadAssumptions(initialBalance, timeChunk);
    _initialInvestorStakeSetup(initialBalance);
    vm.startPrank(investor1);
    ramp.stake(initialBalance);
    assertEq(iou.balanceOf(address(ramp)), initialBalance);
    vm.stopPrank();
    (
      uint256 stakedIOUs,
      uint256 pendingdivs,
      uint256 realizeableIOUs,
      uint256 claimableIOUs
    ) =  ramp.userInfo(investor1);
    assertEq(stakedIOUs, initialBalance);
    assertEq(pendingdivs, 0);
    assertEq(realizeableIOUs, 0);
    assertEq(claimableIOUs, 0);
    assertEq(ramp.iouTokensStaked(investor1), initialBalance);
    // Roll forward a value greater than transmutation period so that the toDistribute gets realized
    vm.roll(block.number + timeChunk);
    (
      stakedIOUs,
      pendingdivs,
      realizeableIOUs,
      claimableIOUs
    ) =  ramp.userInfo(investor1);
    assertEq(stakedIOUs, initialBalance);
    assertEq(pendingdivs, initialBalance);
    assertEq(realizeableIOUs, 0);
    assertEq(claimableIOUs, 0);
    assertEq(ramp.iouTokensStaked(investor1), initialBalance);
  }

  function testStakeTwice(uint256 initialBalance) public {
    (initialBalance,) = _loadAssumptions(initialBalance, 0);
    _initialInvestorStakeSetup(initialBalance);
    vm.startPrank(investor1);
    ramp.stake(initialBalance);

  }

  function testUnStakeSimple(uint256 initialBalance, uint256 timeChunk) public {
    (initialBalance, timeChunk) = _loadAssumptions(initialBalance, timeChunk);
    _initialInvestorStakeSetup(initialBalance);
    vm.startPrank(investor1);
    ramp.stake(initialBalance);
    vm.roll(block.number + timeChunk);
    ramp.unstake(initialBalance);
    vm.stopPrank();

    (
      uint256 stakedIOUs,
      uint256 pendingdivs,
      uint256 realizeableIOUs,
      uint256 claimableIOUs
    ) = ramp.userInfo(investor1);
    assertEq(stakedIOUs, 0, "Deposited ious should be 0 after unstaking");
    assertEq(pendingdivs, 0, "Pending divs should be 0 after unstaking");
    assertEq(realizeableIOUs, 0, "Inbucket should be 0 after unstaking without transmuting");
    assertEq(claimableIOUs, 0, "Realised should be 0 after unstaking without transmuting");
    assertEq(iou.balanceOf(investor1), initialBalance, "investor should have its initial iou balance back");
  }

  function testTransmuteSimple(uint256 initialBalance, uint256 timeChunk) public {
    (initialBalance, timeChunk) = _loadAssumptions(initialBalance, timeChunk);
    _initialInvestorStakeSetup(initialBalance);
    vm.startPrank(investor1);
    ramp.stake(initialBalance);
    vm.roll(block.number + timeChunk);
    ramp.realize();
    vm.stopPrank();

    // we expect realize to move pendingdivs -> realizeableIOUs
    (
      uint256 stakedIOUs,
      uint256 pendingdivs,
      uint256 realizeableIOUs,
      uint256 claimableIOUs
    ) = ramp.userInfo(investor1);

    assertEq(stakedIOUs, 0, "deposited ious should be 0 after transmuting");
    assertEq(pendingdivs, 0, "pending divs should be 0 after transmuting");
    assertEq(realizeableIOUs, 0, "realizeableIOUs should not have any tokens after transmuting");
    assertEq(claimableIOUs, initialBalance, "no tokens have been realized yet");
    assertEq(iou.totalSupply(), 0, "all iou tokens should have been burned");

  }

  function testClaimSimple(uint256 initialBalance, uint256 timeChunk) public {

    (initialBalance, timeChunk) = _loadAssumptions(initialBalance, timeChunk);
    _initialInvestorStakeSetup(initialBalance);
    vm.startPrank(investor1);
    ramp.stake(initialBalance);
    vm.roll(block.number + timeChunk);
    ramp.realize();
    ramp.claim();

    (
      uint256 stakedIOUs,
      uint256 pendingdivs,
      uint256 realizeableIOUs,
      uint256 claimableIOUs
    ) =  ramp.userInfo(investor1);

    assertEq(stakedIOUs, 0, "deposited ious should be 0 after transmuting");
    assertEq(pendingdivs, 0, "pending divs should be 0 after transmuting");
    assertEq(realizeableIOUs, 0, "realizeableIOUs should not have any tokens after transmuting");
    assertEq(claimableIOUs, 0, "no tokens have been realized yet");
    assertEq(iou.totalSupply(), 0, "all iou tokens should have been burned");

    assertEq(wFIL.balanceOf(investor1), initialBalance, "investor should have received initialBalance wFIL tokens");
    assertEq(wFIL.balanceOf(address(ramp)), 0, "ramp should have no more wfil balance after claim");
    vm.stopPrank();
  }








  function _initialInvestorStakeSetup(uint256 amount) internal {
    _mintWFILToOfframp(amount);
    vm.prank(address(ramp));
    iou.mint(investor1, amount);
    vm.prank(investor1);
    iou.approve(address(ramp), amount);
  }

  function _mintWFILToOfframp(uint256 amount) internal {
    address investor = makeAddr("INVESTOR");
    vm.deal(investor, amount);
    vm.startPrank(investor);
    wFIL.deposit{value: amount}();
    wFIL.approve(address(ramp), amount);
    ramp.distribute(investor, amount);
    vm.stopPrank();
  }

  function _loadAssumptions(uint256 _initialBalance, uint256 _timeChunk) internal returns(uint256 initialBalance, uint256 timeChunk){
    // We want to test values between reasonable dust and max supply
    initialBalance = bound(_initialBalance, dust, maxSupply);
    timeChunk = bound(_timeChunk, conversionWindow, EPOCHS_IN_20_YEARS);
  }
}
