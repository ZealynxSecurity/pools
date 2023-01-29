// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @dev PowerTokenPlus interface adds the function Mint/Burn to expand the standard ERC20 as defined in the EIP.
 */
interface IPowerTokenPlus {
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

}
