// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IPool} from "src/Types/Interfaces/IPool.sol";

library PoolSnapshot {
    error PoolVarMismatch(string varName, uint256 a, uint256 b);

    struct PoolState {
        uint256 totalBorrowed;
        uint256 totalBorrowableAssets;
        uint256 exitReserve;
        uint256 liquidAssets;
    }

    function snapshot(IPool pool) internal view returns (PoolState memory state) {
        state.totalBorrowed = pool.totalBorrowed();
        state.totalBorrowableAssets = pool.totalBorrowableAssets();
        state.exitReserve = pool.getAbsMinLiquidity();
        state.liquidAssets = pool.getLiquidAssets();
    }

    function mustBeEqual(IPool pool1, PoolState memory pool2State) internal view {
        PoolState memory pool1State = snapshot(pool1);

        // go through each variable and check if they are equal
        if (pool1State.totalBorrowed != pool2State.totalBorrowed) {
            revert PoolVarMismatch("totalBorrowed", pool1State.totalBorrowed, pool2State.totalBorrowed);
        }
        if (pool1State.totalBorrowableAssets != pool2State.totalBorrowableAssets) {
            revert PoolVarMismatch(
                "totalBorrowableAssets", pool1State.totalBorrowableAssets, pool2State.totalBorrowableAssets
            );
        }
        if (pool1State.exitReserve != pool2State.exitReserve) {
            revert PoolVarMismatch("exitReserve", pool1State.exitReserve, pool2State.exitReserve);
        }
        if (pool1State.liquidAssets != pool2State.liquidAssets) {
            revert PoolVarMismatch("liquidAssets", pool1State.liquidAssets, pool2State.liquidAssets);
        }
    }
}
