// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";

interface IPool {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Borrow(uint256 indexed agent, uint256 amount);

    event Pay(uint256 indexed agent, uint256 amount, uint256 interest, uint256 principal, uint256 rate);

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    event WriteOff(uint256 indexed agentID, uint256 recoveredFunds, uint256 lostFunds, uint256 interestPaid);

    event UpdateAccounting(
        address indexed caller,
        uint256 accruedRentalFeesMarginal,
        uint256 accruedRentalFeesTotal,
        uint256 previousAccountingUpdatingEpoch,
        uint256 thisAccountingUpdateEpoch,
        uint256 iFILPrice
    );

    /*////////////////////////////////////////////////////////
                            GETTERS
    ////////////////////////////////////////////////////////*/

    function asset() external view returns (IERC20);

    function liquidStakingToken() external view returns (IPoolToken);

    function id() external view returns (uint256);

    function minimumLiquidity() external view returns (uint256);

    function getAbsMinLiquidity() external view returns (uint256);

    function isShuttingDown() external view returns (bool);

    function totalBorrowed() external view returns (uint256);

    function totalBorrowableAssets() external view returns (uint256);

    function getAgentBorrowed(uint256 agentID) external view returns (uint256);

    function getAgentDebt(uint256 agentID) external view returns (uint256);

    function getAgentInterestOwed(uint256 agentID) external view returns (uint256);

    function getLiquidAssets() external view returns (uint256);

    function lpRewards() external view returns (RewardAccrual memory);

    function treasuryRewards() external view returns (RewardAccrual memory);

    function treasuryFeesOwed() external view returns (uint256);

    function getRate() external view returns (uint256);

    function credParser() external view returns (address);

    function treasuryFeeRate() external view returns (uint256);

    function lastAccountingUpdateEpoch() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            BORROWER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function borrow(VerifiableCredential calldata vc) external;

    function pay(VerifiableCredential calldata vc)
        external
        returns (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund);

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    function harvestFees(uint256 harvestAmount) external;

    /*//////////////////////////////////////////////////////////////
                        4626 DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(address receiver) external payable returns (uint256 shares);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function withdrawF(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function redeemF(uint256 shares, address receiver, address owner) external returns (uint256 assets);

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

    function updateAccounting() external;

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

    function refreshRoutes() external;

    function shutDown() external;

    function decommissionPool(IPool newPool) external returns (uint256 borrowedAmount);

    function jumpStartAccount(address receiver, uint256 agentID, uint256 principal) external;

    function jumpStartTotalBorrowed(uint256 amount) external;

    function setMinimumLiquidity(uint256 minLiquidity) external;

    function setTreasuryFeeRate(uint256 _treasuryFeeRate) external;

    function writeOff(uint256 agentID, uint256 recoveredDebt) external;

    function setRentalFeesOwedPerEpoch(uint256 _rentalFeesOwedPerEpoch) external;

    function recoverFIL(address receiver) external;
}
