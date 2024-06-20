// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {IGLIFToken} from "src/Types/Interfaces/IGLIFToken.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {Ownable} from "src/Auth/Ownable.sol";

contract Token is ERC20, ERC20Burnable, ERC20Votes, ERC20Permit, Ownable {
    using FilAddress for address;

    /// @notice Total supply cap has been exceeded.
    error ERC20ExceededCap(uint256 increasedSupply, uint256 cap);

    /// @notice The only authority that can mint tokens
    address public minter;

    /// @notice The maximum supply of the token, default to 1 billion
    uint256 private _cap = 1_000_000_000e18;

    constructor(string memory _name, string memory _symbol, address _owner, address _minter)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        Ownable(_owner)
    {
        minter = _minter.normalize();
    }

    /*//////////////////////////////////////////////////////////////
          ERC20 METHOD OVERRIDES WITH FIL ADDRESS NORMALIZATION
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address account) public view override(ERC20) returns (uint256) {
        return super.balanceOf(account.normalize());
    }

    function allowance(address owner, address spender) public view override(ERC20) returns (uint256) {
        return super.allowance(owner.normalize(), spender.normalize());
    }

    function approve(address spender, uint256 value) public override(ERC20) returns (bool) {
        return super.approve(spender.normalize(), value);
    }

    function transfer(address to, uint256 value) public override(ERC20) returns (bool) {
        return super.transfer(to.normalize(), value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        return super.transferFrom(from.normalize(), to.normalize(), value);
    }

    /*//////////////////////////////////////////////////////////////
            MINT/BURN METHODS WITH FIL ADDRESS NORMALIZATION
    //////////////////////////////////////////////////////////////*/

    function mint(address account, uint256 value) public {
        // only the miner role can mint
        if (msg.sender != minter) revert Unauthorized();
        // enforce the cap
        uint256 supply = totalSupply() + value;
        if (supply > _cap) revert ERC20ExceededCap(supply, _cap);
        // mint the tokens
        super._mint(account.normalize(), value);
    }

    function burnFrom(address account, uint256 value) public override(ERC20Burnable) {
        super.burnFrom(account.normalize(), value);
    }

    /*//////////////////////////////////////////////////////////////
        REQUIRED METHOD OVERRIDES DUE TO INHERITANCE CONFLICTS
    //////////////////////////////////////////////////////////////*/

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        /// we don't address normalize here because the methods that call _update internall have already been normalized
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner.normalize());
    }

    /*//////////////////////////////////////////////////////////////
      ERC20Permit METHOD OVERRIDES WITH FIL ADDRESS NORMALIZATION
    //////////////////////////////////////////////////////////////*/

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override(ERC20Permit)
    {
        super.permit(owner.normalize(), spender.normalize(), value, deadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
        GOVERNANCE METHOD OVERRIDES WITH FIL ADDRESS NORMALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get number of checkpoints for `account`.
     */
    function numCheckpoints(address account) public view override(ERC20Votes) returns (uint32) {
        return super.numCheckpoints(account.normalize());
    }

    /**
     * @dev Get the `pos`-th checkpoint for `account`.
     */
    function checkpoints(address account, uint32 pos)
        public
        view
        override(ERC20Votes)
        returns (Checkpoints.Checkpoint208 memory)
    {
        return super.checkpoints(account.normalize(), pos);
    }

    /**
     * @dev Returns the current amount of votes that `account` has.
     */
    function getVotes(address account) public view override(Votes) returns (uint256) {
        return super.getVotes(account);
    }

    /**
     * @dev Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value at the end of the corresponding block.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past. If operating using block numbers, the block must be already mined.
     */
    function getPastVotes(address account, uint256 timepoint) public view override(Votes) returns (uint256) {
        return super.getPastVotes(account.normalize(), timepoint);
    }

    /**
     * @dev Returns the delegate that `account` has chosen.
     */
    function delegates(address account) public view override(Votes) returns (address) {
        return super.delegates(account.normalize());
    }

    /**
     * @dev Delegates votes from the sender to `delegatee`.
     */
    function delegate(address delegatee) public override(Votes) {
        super.delegate(delegatee.normalize());
    }

    /**
     * @dev Delegates votes from signer to `delegatee`.
     */
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override(Votes)
    {
        super.delegateBySig(delegatee.normalize(), nonce, expiry, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
            Additional methods added by this Token contract
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the cap on the token's total supply.
     */
    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    /**
     * @notice Increases the value of the `cap` by `increase`
     * @param increase The amount to increase the cap by
     */
    function setCap(uint256 increase) external onlyOwner {
        uint256 increasedCap = _cap + increase;
        // ERC20Votes has a restriction on the max supply of max uint208, as Checkpoints are stored in the rest of the uint256
        // here we enforce the maximum
        if (increasedCap > _maxSupply()) {
            revert ERC20ExceededCap(increase, _cap);
        }
        _cap = increasedCap;
    }

    /**
     * @notice Sets the address of the `minter` who can mint tokens from this contract
     * @param _minter The address of the new minter
     */
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }
}
