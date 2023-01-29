// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @dev PowerToken interface extends the standard ERC20 as defined in the EIP to include the function Mint/Burn.
 */
interface IPowerToken {
    /**
     * @dev Emitted when an Agent calls {mint}
     */
    event MintPower(address indexed agent, uint256 amount);

    /**
     * @dev Emitted when an Agent calls {burn}
     */
    event BurnPower(address indexed agent, uint256 amount);

    /**
     * @dev Emitted when Power Token Admin calls {pause}
     */
    event PauseContract();

    /**
     * @dev Emitted when Power Token Admin calls {resume}
     */
    event ResumeContract();

    /**
     * @dev Returns the amount of power tokens a particular agent has minted
     */
    function powerTokensMinted(uint256 agentID) external view returns (uint256);

    /**
     * @dev Mints the amount of token passed as `amount`
     */
    function mint(uint256 amount) external;

    /**
     * @dev Burns the amount of token passed as `amount`
     */
    function burn(uint256 amount) external;

    /**
     * @dev Pauses the power token contract
     */
    function pause() external;

    /**
     * @dev Unpauses the power token contract
     */
    function resume() external;

     /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

}
