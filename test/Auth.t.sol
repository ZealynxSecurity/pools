// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Ownable} from "src/Auth/Ownable.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {errorSelector} from "test/helpers/Utils.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import "test/BaseTest.sol";

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
    vm.prank(owner);
    operatable.transferOperator(newOperator);
    assertEq(operatable.pendingOperator(), newOperator);
    assertEq(operatable.operator(), operator);
  }

  function testAcceptOperator() public {
    address newOperator = makeAddr("NEW_OPERATOR");
    vm.prank(owner);
    operatable.transferOperator(newOperator);
    vm.prank(newOperator);
    operatable.acceptOperator();
    assertEq(operatable.pendingOperator(), address(0));
    assertEq(operatable.operator(), newOperator);
  }

  function testAcceptOperatorNonPendingOperator() public {
    address newOperator = makeAddr("NEW_OPERATOR");
    vm.prank(owner);
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

contract AgentOwnershipTest is BaseTest {
    IAgent agent;
    IAuth auth;
    uint64 miner;

    function setUp() public {
        address owner = makeAddr("OWNER");
        (agent, miner) = configureAgent(owner);
        auth = IAuth(address(agent));

        // change the operator to a different address than the owner for these tests
        address operator = makeAddr("OPERATOR");
        vm.prank(owner);
        auth.transferOperator(operator);
        vm.prank(operator);
        auth.acceptOperator();
    }

    function testSetChangeOwner() public {
        address currentOwner = _agentOwner(agent);
        address newOwner = makeAddr("NEW_OWNER");
        vm.startPrank(currentOwner);
        auth.transferOwnership(newOwner);
        vm.stopPrank();

        assertEq(_agentOwner(agent), currentOwner, "Agent owner should not be changed");

        vm.startPrank(newOwner);
        auth.acceptOwnership();
        vm.stopPrank();

        assertEq(_agentOwner(agent), newOwner, "Agent owner should be changed");
    }

    function testSetChangeOwnerNonOwner() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.expectRevert(Unauthorized.selector);
        auth.transferOwnership(newOwner);

        vm.startPrank(newOwner);
        vm.expectRevert(Unauthorized.selector);
        auth.acceptOwnership();
    }

    function testSetChangeOperatorAsOwner() public {
        address currentOwner = _agentOwner(agent);
        address currentOperator = _agentOperator(agent);
        address newOperator = makeAddr("NEW_OPERATOR");

        vm.startPrank(currentOwner);
        auth.transferOperator(newOperator);
        vm.stopPrank();

        assertEq(_agentOperator(agent), currentOperator, "Agent operator should not be changed");

        vm.startPrank(newOperator);
        auth.acceptOperator();
        vm.stopPrank();

        assertEq(_agentOperator(agent), newOperator, "Agent operator should be changed");
    }

    function testSetChangeOwnerAsOperator() public {
        address currentOwner = _agentOwner(agent);
        address currentOperator = _agentOperator(agent);
        address newOperator = makeAddr("NEW_OPERATOR");

        vm.startPrank(currentOperator);
        vm.expectRevert(Unauthorized.selector);
        auth.transferOwnership(newOperator);
        vm.stopPrank();

        assertEq(_agentOperator(agent), currentOperator, "Agent operator should not be changed");
        assertEq(_agentOwner(agent), currentOwner, "Agent owner should not be changed");
    }

    function testChangeOperatorAsOperator() public {
        address currentOperator = _agentOperator(agent);
        address newOperator = makeAddr("NEW_OPERATOR");

        vm.startPrank(currentOperator);
        vm.expectRevert(Unauthorized.selector);
        auth.transferOperator(newOperator);
        vm.stopPrank();

        assertEq(_agentOperator(agent), currentOperator, "Agent operator should not be changed");
    }
}