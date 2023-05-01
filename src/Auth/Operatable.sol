// SPDX-License-Identifier: MIT
// Inspired by OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity 0.8.17;

import {FilAddress} from "shim/FilAddress.sol";
import {Ownable} from "src/Auth/Ownable.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an operator) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the operator account will be passed in the constructor. This
 * can later be changed with {transferOperator} and {acceptOperator}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Operatable).
 */
abstract contract Operatable is Ownable {
    using FilAddress for address;

    address public operator;
    address public pendingOperator;

    /**
     * @dev Initializes the contract setting `_initialOperator` as the initial operator.
     */
    constructor(address _owner, address _initialOperator) Ownable(_owner) {
      _initialOperator = _initialOperator.normalize();
      if (_initialOperator == address(0)) revert InvalidParams();
      _transferOperator(_initialOperator);
    }

    /**
     * @dev Throws if called by any account other than the operator.
     *
     * Modifier overriden by the Agent
     */
    modifier onlyOwnerOperator() virtual {
      _checkOwnerOperator();
      _;
    }

    /**
     * @dev Throws if the sender is not the owner or the operator.
     */
    function _checkOwnerOperator() internal view virtual {
      if (operator != msg.sender && owner != msg.sender) revert Unauthorized();
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner or operator.
     */
    function transferOperator(address newOperator) public virtual onlyOwnerOperator {
        pendingOperator = newOperator;
    }


    /**
     * @dev Transfers operator role of the contract to a new account (`newOperator`).
     * Internal function without access restriction.
     */
    function _transferOperator(address newOperator) internal virtual {
      delete pendingOperator;
      operator = newOperator.normalize();
    }

    /**
     * @dev The new operator accepts the ownership transfer.
     */
    function acceptOperator() external {
      if (pendingOperator != msg.sender) revert Unauthorized();
      _transferOperator(msg.sender);
    }
}
