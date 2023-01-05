// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;
import {PoolToken} from "../../Pool/Tokens/PoolToken.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
/// NOTE: this pool uses accrual basis accounting to compute share prices
interface IPool  {
    // Basic Stats Getters **PURE**
    function template() external view returns (IPoolTemplate);
    function share() external view returns (PoolToken);
    function getAgentBorrowed(address agent) external view returns (uint256);
    function getAgentBorrowed(Account memory account) external view returns (uint256);
    function pmtPerPeriod(address agent) external view returns (uint256);
    function pmtPerPeriod(Account memory account) external view returns (uint256);
    function totalBorrowed() external view returns (uint256);
    function getPowerToken() external view returns (IPowerToken);
    // Would love to expose the public getter but not sure how to with the interitance structure we have
    function getAsset() external view returns (ERC20);
    function getAccount(address agent) external view returns (Account calldata);
    function setAccount(Account memory account, address owner) external;
    function resetAccount(address owner) external;
    function reduceTotalBorrowed(uint256 amount) external;
    function increaseTotalBorrowed(uint256 amount) external;
    // Finance functions
    function borrow(
        uint256 amount,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    ) external returns (uint256);
    function exitPool(
        address agent,
        SignedCredential memory sc,
        uint256 amount
    ) external returns (uint256);
    function makePayment(
        address agent,
        uint256 amount
    ) external;
    function stakeToPay(
        uint256 pmt,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    ) external;
    // Admin Funcs
    function flush() external;
    
    /*//////////////////////////////////////////////////////////////
                        4626 DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256 assets);

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    function previewMint(uint256 shares) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) external view returns (uint256);

    function maxMint(address) external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function maxRedeem(address owner) external view returns (uint256);

}

