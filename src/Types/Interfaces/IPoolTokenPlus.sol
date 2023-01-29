// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev PoolTokenPlus defines the additional functions an IPoolToken must extend in additon
        to the ERC20 interface to include minting and burning.
 */
interface IPoolTokenPlus {
    /**
     * @dev Returns the poolID of the pool this token belongs to.
     */
    function poolID() external view returns (uint256);
    /**
     * @dev Mints PoolTokens. Protected call.
     */
    function mint(address account, uint256 amount) external returns (bool);
    /**
     * @dev Burns PoolTokens. Protected call.
     */
    function burn(address account, uint256 amount) external returns (bool);
}
