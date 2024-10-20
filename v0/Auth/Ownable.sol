// SPDX-License-Identifier: MIT
// Inspired by OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

// solhint-disable
pragma solidity ^0.8.17;

import {FilAddress} from "shim/FilAddress.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be passed in the constructor. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable {
    error Unauthorized();
    error InvalidParams();

    using FilAddress for address;

    address public owner;
    address public pendingOwner;

    /**
     * @dev Initializes the contract setting `owner` as the initial owner.
     */
    constructor(address _initialOwner) {
        _initialOwner = _initialOwner.normalize();
        if (_initialOwner == address(0)) revert InvalidParams();

        _transferOwnership(_initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner != msg.sender) revert Unauthorized();
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        pendingOwner = newOwner.normalize();
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        delete pendingOwner;
        owner = newOwner.normalize();
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() external {
        if (pendingOwner != msg.sender) revert Unauthorized();
        _transferOwnership(msg.sender);
    }
}
