// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {Ownable} from "src/Auth/Ownable.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {ROUTE_CRED_PARSER} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

contract RateModule is IRateModule, Ownable {

    using Credentials for VerifiableCredential;

    uint256 constant WAD = 1e18;

    /// @dev `maxDTI` is the maximum ratio of expected daily interest payments to expected daily rewards (1)
    uint256 public maxDTI = 0.5e18;

    /// @dev `maxLTV` is the maximum ratio of principal to collateral
    uint256 public maxLTV = 0.95e18;

    /// @dev `minGCRED` is the minimum GCRED value for an Agent to be eligible for borrowing
    uint256 public minGCRED = 40;

    /// @dev `rateLookup` is a memoized GCRED => rateMultiplier lookup table. It sets the interest curve
    uint256[100] public rateLookup;

    /// @dev `credParser` is the cached cred parser
    address public credParser;

    address public router;

    constructor(
        address _owner,
        address _router,
        uint256[100] memory _rateLookup
    ) Ownable(_owner) {
        router = _router;
        credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
        rateLookup = _rateLookup;
    }

    function lookupRate(uint256 gcred) external view returns (uint256) {
        return rateLookup[gcred];
    }

    /**
    * @notice getRate returns the rate for an Agent's current position within the Pool
    * rate is based on the formula base rate  e^(bias * (100 - GCRED)) where the exponent is pulled from a lookup table
    */
    function getRate(
        Account memory account,
        VerifiableCredential memory vc
    ) public view returns (uint256) {
        return _getRate(vc.getBaseRate(credParser), vc.getGCRED(credParser));
    }

    /**
     * @notice isApproved returns false if the Agent is in a bad state (over leveraged, not on whitelist..etc)
     * The bulk of this check is around:
     * 1. Minimum GCRED score
     * 2. Maximum loan-to-value ratio, where the loan is the total agent's principal, and the value is the total Agent's locked funds in pledge collateral + vesting rewards on filecoin
     * 3. Maximum debt-to-income ratio, where the debt is the total agent's interest payments, and the income is the weighted agent's expected daily rewards
     */
    function isApproved(
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (bool) {
        // if you have nothing borrowed, you're good no matter what
        uint256 totalPrincipal = vc.getPrincipal(credParser);
        if (totalPrincipal == 0) return true;
        // if you have bad GCRED, you're not approved
        uint256 gcred = vc.getGCRED(credParser);
        if (gcred < minGCRED) return false;
        // if you have no collateral, it's an automatic no
        uint256 totalLockedFunds = vc.getLockedFunds(credParser);
        if (totalLockedFunds == 0) return false;

        // if LTV is greater than `maxLTV` (e18 denominated), we are over leveraged (can't mortgage more than the value of your home)
        if (_computeLTV(totalPrincipal, totalLockedFunds) > maxLTV) {
            return false;
        }

        return _computeDTI(
            vc.getExpectedDailyRewards(credParser),
            _getRate(vc.getBaseRate(credParser), gcred),
            account.principal,
            totalPrincipal
        ) <= maxDTI;
    }

    function setMaxDTI(uint256 _maxDTI) external onlyOwner {
        maxDTI = _maxDTI;
    }

    function setMaxLTV(uint256 _maxLTV) external onlyOwner {
        maxLTV = _maxLTV;
    }

    function setMinGCRED(uint256 _minGCRED) external onlyOwner {
        minGCRED = _minGCRED;
    }

    function setRateLookup(uint256[100] memory _rateLookup) external onlyOwner {
        rateLookup = _rateLookup;
    }

    function updateCredParser() external onlyOwner {
        credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    }

    /// @dev compute the loan to value, where value is locked funds
    function _computeLTV(
        uint256 totalPrincipal,
        uint256 totalLockedFunds
    ) internal view returns (uint256) {
        // compute the loan to value
        return totalPrincipal * WAD / totalLockedFunds;
    }

    /// @dev compute the DTI
    function _computeDTI(
        uint256 expectedDailyRewards,
        uint256 rate,
        uint256 accountPrincipal,
        uint256 totalPrincipal
    ) internal view returns (uint256) {
        uint256 equityPercentage = (accountPrincipal * WAD) / totalPrincipal;
        // compute the % of EDR this pool can rely on
        uint256 weightedEDR = (equityPercentage * expectedDailyRewards) / WAD;
        // if the EDR is too low, we return the highest DTI
        if (weightedEDR == 0) return type(uint256).max;

        // compute expected daily payments to align with expected daily reward
        uint256 dailyRate = rate * EPOCHS_IN_DAY * accountPrincipal;
        // compute DTI
        return dailyRate / weightedEDR;
    }

    function _getRate(uint256 baseRate, uint256 gcred) internal view returns (uint256) {
        return (baseRate * rateLookup[gcred]) / WAD;
    }
}
