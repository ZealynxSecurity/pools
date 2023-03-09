// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;
import {ERC20} from "solmate/tokens/ERC20.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";

interface IPool {

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event RebalanceTotalBorrowed(
        uint256 indexed agentID,
        uint256 realAccountValue,
        uint256 totalBorrowed
    );

    event SetOperatorRole(address indexed operator, bool enabled);

    /*////////////////////////////////////////////////////////
                            GETTERS
    ////////////////////////////////////////////////////////*/

    function asset() external view returns (ERC20);

    function share() external view returns (PoolToken);

    function template() external view returns (IPoolTemplate);

    function implementation() external view returns (IPoolImplementation);

    function iou() external view returns (PoolToken);

    function ramp() external view returns (IOffRamp);

    function id() external view returns (uint256);

    function minimumLiquidity() external view returns (uint256);

    function getAbsMinLiquidity() external view returns (uint256);

    function isShuttingDown() external view returns (bool);

    function totalBorrowed() external view returns (uint256);

    function totalBorrowableAssets() external view returns (uint256);

    function getAgentBorrowed(uint256 agentID) external view returns (uint256);

    function getLiquidAssets() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            BORROWER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function borrow(uint256 amount, SignedCredential memory sc, uint256 powerTokenAmount) external;

    function exitPool( address agent, SignedCredential memory sc, uint256 amount) external returns (uint256);

    function makePayment(address agent,uint256 pmt) external;

    function stakeToPay(uint256 pmt, SignedCredential memory sc, uint256 powerTokenAmount) external;

    function rebalanceTotalBorrowed(uint256 agentID, uint256 realAccountValue) external;

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvestFees(uint256 harvestAmount) external;

    function harvestToRamp() external;

    /*//////////////////////////////////////////////////////////////
                        4626 DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(address receiver) external payable returns (uint256 shares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

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

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCS
    //////////////////////////////////////////////////////////////*/

    function shutDown() external;

    function decommissionPool(IPool newPool) external returns (uint256 borrowedAmount);

    function jumpStartTotalBorrowed(uint256 amount) external;

    function setRamp(IOffRamp newRamp) external;

    function setTemplate(IPoolTemplate newTemplate) external;

    function setImplementation(IPoolImplementation poolImplementation) external;

    function setMinimumLiquidity(uint256 minLiquidity) external;

    function setOperatorRole(address operator, bool enabled) external;

    /*////////////////////////////////////////////////////////
                    ONLY CALLABLE BY TEMPLATE
    ////////////////////////////////////////////////////////*/

    function reduceTotalBorrowed(uint256 amount) external;

    function increaseTotalBorrowed(uint256 amount) external;
}

