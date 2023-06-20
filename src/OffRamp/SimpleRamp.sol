// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {GetRoute} from "src/Router/GetRoute.sol";

import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";

contract InfPoolSimpleRamp is IOffRamp {
    error Unauthorized();
    error InsufficientLiquidity();

    address private immutable router;
    uint256 private immutable poolID;

    IPool public pool;
    IPoolToken public iFIL;
    IWFIL public wFIL;

    uint256 internal tmpExitDemand = 0;

    modifier receiverMatchesOwner(address receiver, address owner) {
        if (receiver != owner) revert Unauthorized();
        _;
    }

    modifier onlyPool() {
        if (msg.sender != address(pool)) revert Unauthorized();
        _;
    }

    constructor(address _router, uint256 _poolID) {
        router = _router;
        poolID = _poolID;

        _refreshExtern();
    }

    function totalExitDemand() external view returns (uint256) {
        return tmpExitDemand;
    }

    /// @notice Returns the maximum amount of assets (wFIL) that can be withdrawn from the ramp by `account`
    function maxWithdraw(address account) external view returns (uint256) {
        return
            Math.min(
                pool.convertToAssets(iFIL.balanceOf(account)),
                pool.getLiquidAssets()
            );
    }

    /// @notice Returns an onchain simulation of how many shares would be burn to withdraw assets, will revert if not enough assets to exit
    function previewWithdraw(
        uint256 assets
    ) external view returns (uint256 maxAssets) {
        if (assets > pool.getLiquidAssets()) revert InsufficientLiquidity();
        return pool.convertToShares(assets);
    }

    function maxRedeem(
        address account
    ) external view returns (uint256 maxShares) {
        uint256 accountShares = iFIL.balanceOf(account);
        uint256 filValOfShares = pool.convertToAssets(iFIL.balanceOf(account));

        // if the fil value of the account's shares is bigger than the available exit liquidity
        // return the share equivalent of the pool's total liquid assets
        if (filValOfShares > pool.getLiquidAssets()) {
            return pool.convertToShares(pool.getLiquidAssets());
        }

        return accountShares;
    }

    function previewRedeem(
        uint256 shares
    ) external view returns (uint256 assets) {
        assets = pool.convertToAssets(shares);

        // revert if the fil value of the account's shares is bigger than the available exit liquidity
        if (assets > pool.getLiquidAssets()) revert InsufficientLiquidity();
    }

    /**
     * @notice Allows Staker to withdraw assets
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets (this must be )
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256
    ) public receiverMatchesOwner(receiver, owner) returns (uint256 shares) {
        shares = pool.convertToShares(assets);
        _processExit(receiver, shares, assets);
    }

    /**
     * @dev Allows the Staker to redeem their shares for assets
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256
    ) public receiverMatchesOwner(receiver, owner) returns (uint256 assets) {
        assets = pool.convertToAssets(shares);
        _processExit(receiver, shares, assets);
    }

    function _processExit(
        address exiter,
        uint256 iFILToBurn,
        uint256 assetsToReceive
    ) internal {
        // if the pool can't process the entire exit, it reverts
        if (assetsToReceive > pool.getLiquidAssets())
            revert InsufficientLiquidity();
        // this contract will burn any excess iFIL it has (this shouldn't happen, but in case it does, we dont have accounting issues)
        uint256 balanceOfBefore = iFIL.balanceOf(address(this));
        // pull in the iFIL from the iFIL holder, which will decrease the allowance of this ramp to spend on behalf of the iFIL holder
        iFIL.transferFrom(exiter, address(this), iFILToBurn);
        // burn the exiter's iFIL tokens (and any additional iFIL tokens that somehow ended up here)
        iFIL.burn(
            address(this),
            iFIL.balanceOf(address(this)) - balanceOfBefore
        );

        // mark tmpExitDemand such that `ramp.totalExitDemand` returns the amount of FIL this ramp needs
        // in order to process the entire exit
        tmpExitDemand = assetsToReceive;
        // move FIL from the pool into the ramp to process the exit
        // note that `tmpExitDemand` is used by the pool to determine how much FIL to send to the ramp
        // and gets written down to 0 in the `distribute` function (which pulls the assets into the ramp)
        pool.harvestToRamp();
        // send WFIL back to the exiter (instead of FIL, better for downstream contracts)
        wFIL.transfer(exiter, assetsToReceive);
        // in the event that WFIL exists in this contract, we forward any remaining balances back to the pool
        wFIL.transfer(address(pool), wFIL.balanceOf(address(this)));
    }

    /**
     * @notice recoverFIL takes any FIL in this contract, wraps it, and transfers it to the Infinity Pool
     */
    function recoverFIL() external {
        uint256 value = address(this).balance;
        wFIL.deposit{value: value}();
        wFIL.transfer(address(pool), value);
    }

    /**
     * @notice distribute is called by the Infinity Pool in `harvestToRamp` which first approves the ramp to spend WFIL
     * @param amount The amount of WFIL to distribute - note this amount is equal to `totalExitDemand` when called
     */
    function distribute(address, uint256 amount) external onlyPool {
        // transfer the assets from the pool of amount into the ramp
        wFIL.transferFrom(address(pool), address(this), amount);
        // reset exit demand to 0 once the assets are moved in
        tmpExitDemand = 0;
    }

    function refreshExtern() external {
        _refreshExtern();
    }

    function _refreshExtern() internal {
        pool = GetRoute.pool(GetRoute.poolRegistry(router), poolID);
        iFIL = pool.liquidStakingToken();
        wFIL = IWFIL(address(pool.asset()));
    }
}
