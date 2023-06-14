// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {errorSelector} from "test/helpers/Utils.sol";
error Unauthorized();

contract OwnableMock is Ownable {
  uint256 public protectedCounter = 0;

  constructor(address _initialOwner) Ownable(_initialOwner) {}

  function plusOne() public onlyOwner {
    protectedCounter++;
  }
}

contract OwnableTest is Test {
  OwnableMock ownable;
  address owner = makeAddr("OWNER");

  function setUp() public {
    ownable = new OwnableMock(owner);
  }

  function testOwner() public {
    assertEq(ownable.owner(), owner);
    assertEq(ownable.pendingOwner(), address(0));
  }

  function testProtectedFuncAsOwner() public {
    uint256 preCount = ownable.protectedCounter();
    vm.prank(owner);
    ownable.plusOne();
    assertEq(ownable.protectedCounter(), preCount + 1);
  }

  function testProtectedFuncAsNonOwner() public {
    vm.prank(makeAddr("NOT_OWNER"));
    try ownable.plusOne() {
      assertTrue(false, "should have failed");
    } catch (bytes memory err) {
      assertEq(errorSelector(err), Unauthorized.selector);
    }
  }

  function testTransferOwnership() public {
    address newOwner = makeAddr("NEW_OWNER");
    vm.prank(owner);
    ownable.transferOwnership(newOwner);
    assertEq(ownable.pendingOwner(), newOwner);
    assertEq(ownable.owner(), owner);
  }

  function testAcceptOwnership() public {
    address newOwner = makeAddr("NEW_OWNER");
    vm.prank(owner);
    ownable.transferOwnership(newOwner);
    vm.prank(newOwner);
    ownable.acceptOwnership();
    assertEq(ownable.pendingOwner(), address(0));
    assertEq(ownable.owner(), newOwner);
  }

  function testAcceptOwnershipNonPendingOwner() public {
    address newOwner = makeAddr("NEW_OWNER");
    vm.prank(owner);
    ownable.transferOwnership(newOwner);
    vm.startPrank(makeAddr("NOT_PENDING_OWNER"));
    try ownable.acceptOwnership() {
      assertTrue(false, "should have failed");
    } catch (bytes memory err) {
      assertEq(errorSelector(err), Unauthorized.selector);
    }

    vm.stopPrank();
  }
}

contract OperatableMock is Operatable {
  uint256 public protectedCounter = 0;

  constructor(address _owner, address _initialOperator) Operatable(_owner, _initialOperator) {}

  function plusOne() public onlyOwnerOperator {
    protectedCounter++;
  }
}

contract OperatableTest is Test {
  OperatableMock operatable;
  address operator = makeAddr("OPERATOR");
  address owner = makeAddr("OWNER");

  function setUp() public {
    operatable = new OperatableMock(owner, operator);
  }

  function testOperator() public {
    assertEq(operatable.operator(), operator);
    assertEq(operatable.pendingOperator(), address(0));
  }

  function testProtectedFuncAsOperator() public {
    uint256 preCount = operatable.protectedCounter();
    vm.prank(operator);
    operatable.plusOne();
    assertEq(operatable.protectedCounter(), preCount + 1);
  }

  function testProtectedFuncAsNonOperator() public {
    vm.prank(makeAddr("NOT_OPERATOR"));
    try operatable.plusOne() {
      assertTrue(false, "should have failed");
    } catch (bytes memory err) {
      assertEq(errorSelector(err), Unauthorized.selector);
    }
  }

  function testTransferOperator() public {
    address newOperator = makeAddr("NEW_OPERATOR");
    vm.prank(operator);
    operatable.transferOperator(newOperator);
    assertEq(operatable.pendingOperator(), newOperator);
    assertEq(operatable.operator(), operator);
  }

  function testAcceptOperator() public {
    address newOperator = makeAddr("NEW_OPERATOR");
    vm.prank(operator);
    operatable.transferOperator(newOperator);
    vm.prank(newOperator);
    operatable.acceptOperator();
    assertEq(operatable.pendingOperator(), address(0));
    assertEq(operatable.operator(), newOperator);
  }

  function testAcceptOperatorNonPendingOperator() public {
    address newOperator = makeAddr("NEW_OPERATOR");
    vm.prank(operator);
    operatable.transferOperator(newOperator);
    vm.startPrank(makeAddr("NOT_PENDING_OPERATOR"));
    try operatable.acceptOperator() {
      assertTrue(false, "should have failed");
    } catch (bytes memory err) {
      assertEq(errorSelector(err), Unauthorized.selector);
    }

    vm.stopPrank();
  }
}
