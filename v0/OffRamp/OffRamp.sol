// SPDX-License-Identifier: BUSL-1.1
//solhint-disable
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {GetRoute} from "v0/Router/GetRoute.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";

import {IERC4626} from "v0/Types/Interfaces/IERC4626.sol";
import {IPoolToken} from "v0/Types/Interfaces/IPoolToken.sol";
import {IPool} from "v0/Types/Interfaces/IPool.sol";
import {IWFIL} from "v0/Types/Interfaces/IWFIL.sol";
import {IOffRamp} from "v0/Types/Interfaces/IOffRamp.sol";

contract SimpleRamp is IOffRamp {
    using FixedPointMathLib for uint256;
    using FilAddress for address;
    using FilAddress for address payable;

    error Unauthorized();
    error InsufficientLiquidity();

    address private immutable router;
    uint256 private immutable poolID;

    IPool public pool;
    IPoolToken public iFIL;
    IWFIL public wFIL;

    uint256 internal tmpExitDemand = 0;

    modifier ownerIsCaller(address owner) {
        if (msg.sender != owner.normalize()) revert Unauthorized();
        _;
    }

    modifier onlyPool() {
        if (msg.sender != address(pool)) revert Unauthorized();
        _;
    }

    modifier onlyWFIL() {
        if (msg.sender != address(wFIL)) revert Unauthorized();
        _;
    }

    modifier poolNotUpgraded() {
        if (pool.isShuttingDown()) {
            if (
                address(pool) !=
                address(GetRoute.pool(GetRoute.poolRegistry(router), poolID))
            ) revert Unauthorized();
        }
        _;
    }

    // these fallback and receiver hooks only exist to unwrap WFIL for processing exits
    fallback() external payable onlyWFIL {}

    receive() external payable onlyWFIL {}

    constructor(address _router, uint256 _poolID) {
        router = _router;
        poolID = _poolID;

        _refreshExtern();
    }

    function totalExitDemand() external view returns (uint256) {
        return tmpExitDemand;
    }

    /// @notice Returns the maximum amount of assets (wFIL) that can be withdrawn from the ramp by `account`
    function maxWithdraw(
        address account
    ) external view poolNotUpgraded returns (uint256) {
        return
            Math.min(
                pool.convertToAssets(iFIL.balanceOf(account)),
                pool.getLiquidAssets()
            );
    }

    /// @notice Returns an onchain simulation of how many shares would be burn to withdraw assets, will revert if not enough assets to exit
    function previewWithdraw(
        uint256 assets
    ) public view poolNotUpgraded returns (uint256 shares) {
        if (assets > pool.getLiquidAssets()) return 0;

        uint256 supply = iFIL.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        shares = supply == 0
            ? assets
            : assets.mulDivUp(supply, pool.totalAssets());
    }

    function maxRedeem(
        address account
    ) external view poolNotUpgraded returns (uint256 shares) {
        shares = iFIL.balanceOf(account);
        uint256 filValOfShares = pool.convertToAssets(shares);

        // if the fil value of the account's shares is bigger than the available exit liquidity
        // return the share equivalent of the pool's total liquid assets
        if (filValOfShares > pool.getLiquidAssets()) {
            return previewRedeem(pool.getLiquidAssets());
        }
    }

    function previewRedeem(
        uint256 shares
    ) public view poolNotUpgraded returns (uint256 assets) {
        uint256 supply = iFIL.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        assets = supply == 0
            ? shares
            : shares.mulDivUp(pool.totalAssets(), supply);
        // revert if the fil value of the account's shares is bigger than the available exit liquidity
        if (assets > pool.getLiquidAssets()) return 0;
    }

    /**
     * @notice Allows Staker to withdraw assets (WFIL)
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256
    ) public poolNotUpgraded ownerIsCaller(owner) returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, false);
    }

    /**
     * @dev Allows the Staker to redeem their shares for assets (WFIL)
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
    ) public poolNotUpgraded ownerIsCaller(owner) returns (uint256 assets) {
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, false);
    }

    /**
     * @notice Allows Staker to withdraw assets (FIL)
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdrawF(
        uint256 assets,
        address receiver,
        address owner,
        uint256
    ) public poolNotUpgraded ownerIsCaller(owner) returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, true);
    }

    /**
     * @dev Allows the Staker to redeem their shares for assets (FIL)
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeemF(
        uint256 shares,
        address receiver,
        address owner,
        uint256
    ) public poolNotUpgraded ownerIsCaller(owner) returns (uint256 assets) {
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, true);
    }

    function _processExit(
        address owner,
        address receiver,
        uint256 iFILToBurn,
        uint256 assetsToReceive,
        bool shouldConvert
    ) internal {
        // normalize to protect against sending to ID address of EVM actor
        receiver = receiver.normalize();
        owner = owner.normalize();
        // if the pool can't process the entire exit, it reverts
        if (assetsToReceive > pool.getLiquidAssets())
            revert InsufficientLiquidity();
        // pull in the iFIL from the iFIL holder, which will decrease the allowance of this ramp to spend on behalf of the iFIL holder
        iFIL.transferFrom(owner, address(this), iFILToBurn);
        // burn the exiter's iFIL tokens
        iFIL.burn(address(this), iFILToBurn);

        // mark tmpExitDemand such that `ramp.totalExitDemand` returns the amount of FIL this ramp needs
        // in order to process the entire exit
        tmpExitDemand = assetsToReceive;
        // move FIL from the pool into the ramp to process the exit
        // note that `tmpExitDemand` is used by the pool to determine how much FIL to send to the ramp
        // and gets written down to 0 in the `distribute` function (which pulls the assets into the ramp)
        pool.harvestToRamp();

        // here we unwrap the amount of WFIL and transfer native FIL to the receiver
        if (shouldConvert) {
            // unwrap the WFIL into FIL
            wFIL.withdraw(assetsToReceive);
            // send FIL to the receiver, normalize to protect against sending to ID address of EVM actor
            payable(receiver).sendValue(assetsToReceive);
        } else {
            // send WFIL back to the receiver
            wFIL.transfer(receiver, assetsToReceive);
        }

        emit Withdraw(owner, receiver, owner, assetsToReceive, iFILToBurn);
    }

    /**
     * @notice recoverFIL takes any WFIL and FIL in this contract, wraps it, and transfers it to the Infinity Pool
     */
    function recoverFIL() external {
        uint256 value = address(this).balance;
        wFIL.deposit{value: value}();
        wFIL.transfer(address(pool), wFIL.balanceOf(address(this)));
    }

    /**
     * @notice burnIFIL burns all the iFIL in this contract (this should never happen, but just in case, this fixes any accounting issues)
     */
    function burnIFIL() external {
        iFIL.burn(address(this), iFIL.balanceOf(address(this)));
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
