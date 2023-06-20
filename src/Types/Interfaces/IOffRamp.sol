// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";

interface IOffRamp {
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    function pool() external view returns (IPool);

    function iFIL() external view returns (IPoolToken);

    function wFIL() external view returns (IWFIL);

    function totalExitDemand() external view returns (uint256);

    function maxWithdraw(address account) external view returns (uint256);

    function maxRedeem(address account) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function previewRedeem(uint256 assets) external view returns (uint256);

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 totalAssets
    ) external returns (uint256 assets);

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 totalAssets
    ) external returns (uint256 shares);

    function distribute(address receiver, uint256 amount) external;

    function recoverFIL() external;
}
