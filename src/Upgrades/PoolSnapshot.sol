// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IPool} from "src/Types/Interfaces/IPool.sol";

library PoolSnapshot {
    error TotalAssetsMismatch(uint256 a, uint256 b);
    error TotalBorrowedMismatch(uint256 a, uint256 b);
    error IFILPriceMismatch(uint256 a, uint256 b);
    error TotalBorrowableAssetsMismatch(uint256 a, uint256 b);
    error LiquidAssetsMismatch(uint256 a, uint256 b);
    error MinLiquidityMismatch(uint256 a, uint256 b);

    struct PoolState {
        uint256 totalAssets;
        uint256 totalBorrowed;
        uint256 iFILPrice;
        uint256 totalBorrowableAssets;
        uint256 liquidAssets;
        uint256 minLiquidity;
    }

    function snapshot(IPool pool) internal view returns (PoolState memory state) {
        state.totalAssets = pool.totalAssets();
        state.totalBorrowed = pool.totalBorrowed();
        state.iFILPrice = pool.convertToAssets(1e18);
        state.totalBorrowableAssets = pool.totalBorrowableAssets();
        state.liquidAssets = pool.getLiquidAssets();
        state.minLiquidity = pool.minimumLiquidity();
    }

    function mustBeEqual(IPool pool1, PoolState memory pool2State) internal view {
        PoolState memory pool1State = snapshot(pool1);

        // go through each variable and check if they are equal
        if (pool1State.totalAssets != pool2State.totalAssets) {
            revert TotalAssetsMismatch(pool1State.totalAssets, pool2State.totalAssets);
        }
        if (pool1State.totalBorrowed != pool2State.totalBorrowed) {
            revert TotalBorrowedMismatch(pool1State.totalBorrowed, pool2State.totalBorrowed);
        }
        if (pool1State.iFILPrice != pool2State.iFILPrice) {
            revert IFILPriceMismatch(pool1State.iFILPrice, pool2State.iFILPrice);
        }
        if (pool1State.totalBorrowableAssets != pool2State.totalBorrowableAssets) {
            revert TotalBorrowableAssetsMismatch(pool1State.totalBorrowableAssets, pool2State.totalBorrowableAssets);
        }
        if (pool1State.liquidAssets != pool2State.liquidAssets) {
            revert LiquidAssetsMismatch(pool1State.liquidAssets, pool2State.liquidAssets);
        }
        if (pool1State.minLiquidity != pool2State.minLiquidity) {
            revert MinLiquidityMismatch(pool1State.minLiquidity, pool2State.minLiquidity);
        }
    }
}
