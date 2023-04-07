// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

contract RateModule is IRateModule, Ownable {

    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    /// @dev `maxDTI` is the maximum ratio of expected daily interest payments to expected daily rewards
    uint256 public maxDTI = 0.5e18;

    /// @dev `maxDTE` is the maximum ratio of principal to equity (principal / (agentValue - principal))
    uint256 public maxDTE = 3e18;

    /// @dev `maxLTV` is the maximum ratio of principal to collateral
    uint256 public maxLTV = 1e18;

    /// @dev `minGCRED` is the minimum GCRED value for an Agent to be eligible for borrowing
    uint256 public minGCRED = 40;

    /// @dev `rateLookup` is a memoized GCRED => rateMultiplier lookup table. It sets the interest curve
    uint256[61] public rateLookup;

    /// @dev `levels` is a leveling system that sets maximum borrow amounts on accounts
    uint256[10] public levels;

    /// @dev `baseRate` floats according to the market, and is multiplied against the riskMultiplier to set the interest rate
    uint256 public baseRate = 18e16;

    /// @dev `accountLevel` is a mapping of agentID to level
    mapping(uint256 => uint256) public accountLevel;

    /// @dev `credParser` is the cached cred parser
    address public credParser;

    address public router;

    constructor(
        address _owner,
        address _router,
        uint256[61] memory _rateLookup,
        uint256[10] memory _levels
    ) Ownable(_owner) {
        router = _router;
        credParser = address(GetRoute.credParser(router));
        rateLookup = _rateLookup;
        levels = _levels;
    }
    /**
    * @notice getRate returns the rate for an Agent's current position within the Pool
    * rate is based on the formula base rate  e^(bias * (100 - GCRED)) where the exponent is pulled from a lookup table
    */
    function getRate(
        Account memory account,
        VerifiableCredential memory vc
    ) public view returns (uint256) {
        return _getRate(vc.getGCRED(credParser));
    }

    /**
     * @notice _getRate returns the rate for an Agent's current position within the Pool
     * rate is based on the formula base rate  e^(bias * (100 - GCRED)) where the exponent is pulled from a lookup table
     */
    function penaltyRate() external view returns (uint256) {
        return _getRate(minGCRED);
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
        // if you're behind on your payments, you're not approved
        if (account.epochsPaid + GetRoute.agentPolice(router).defaultWindow() < block.number) {
            return false;
        }

        // if you're attempting to borrow above your level limit, you're not approved
        if (account.principal > levels[accountLevel[vc.subject]]) {
            return false;
        }

        uint256 totalPrincipal = vc.getPrincipal(credParser);
        // if you have nothing borrowed, you're good no matter what
        if (totalPrincipal == 0) return true;
        // if you have bad GCRED, you're not approved
        uint256 gcred = vc.getGCRED(credParser);
        if (gcred < minGCRED) return false;
        // if you have no collateral, it's an automatic no
        uint256 collateralValue = vc.getCollateralValue(credParser);
        if (collateralValue == 0) return false;

        // if LTV is greater than `maxLTV` (e18 denominated), we are over leveraged (can't mortgage more than the value of your home)
        if (computeLTV(totalPrincipal, collateralValue) > maxLTV) {
            return false;
        }

        if (computeDTE(totalPrincipal, vc.getAgentValue(credParser)) > maxDTE) {
            return false;
        }

        return computeDTI(
            vc.getExpectedDailyRewards(credParser),
            _getRate(gcred),
            account.principal,
            totalPrincipal
        ) <= maxDTI;
    }

    function setMaxDTI(uint256 _maxDTI) external onlyOwner {
        maxDTI = _maxDTI;
    }

    function setMaxDTE(uint256 _maxDTE) external onlyOwner {
        maxDTE = _maxDTE;
    }

    function setMaxLTV(uint256 _maxLTV) external onlyOwner {
        maxLTV = _maxLTV;
    }

    function setMinGCRED(uint256 _minGCRED) external onlyOwner {
        minGCRED = _minGCRED;
    }

    function setRateLookup(uint256[61] calldata _rateLookup) external onlyOwner {
        rateLookup = _rateLookup;
    }

    function setBaseRate(uint256 _baseRate) external onlyOwner {
        baseRate = _baseRate;
    }

    function updateCredParser() external onlyOwner {
        credParser = address(GetRoute.credParser(router));
    }

    function setLevels(uint256[10] calldata _levels) external onlyOwner {
        levels = _levels;
    }

    function setAgentLevels(uint256[] calldata agentIDs, uint256[] calldata level) external onlyOwner {
        if (agentIDs.length != level.length) revert InvalidParams();
        uint256 i = 0;
        for (; i < agentIDs.length; i++) {
          accountLevel[agentIDs[i]] = level[i];
        }
    }

    /// @dev compute the loan to value, where value is locked funds
    function computeLTV(
        uint256 totalPrincipal,
        uint256 collateralValue
    ) public pure returns (uint256) {
        // compute the loan to value
        return totalPrincipal.divWadDown(collateralValue);
    }

    /// @dev compute the DTI
    function computeDTI(
        uint256 expectedDailyRewards,
        uint256 rate,
        uint256 accountPrincipal,
        uint256 totalPrincipal
    ) public pure returns (uint256) {
        // equityPercentage now has an extra WAD factor for precision
        uint256 equityPercentage = accountPrincipal.divWadDown(totalPrincipal);
        // compute the % of EDR this pool can rely on
        // mulWadDown here cancels the extra WAD factor in equityPercentage
        uint256 weightedEDR = equityPercentage.mulWadDown(expectedDailyRewards);
        // if the EDR is too low, we return the highest DTI
        if (weightedEDR == 0) return type(uint256).max;

        // compute expected daily payments to align with expected daily reward
        // `rate` has an extra WAD factor for precision, and accountPrincipal is already in WAD
        // so mulWadUp by EPOCHS_IN_DAY cancels the extra WAD factor in `rate` to get a daily rate in WAD
        uint256 dailyRate = accountPrincipal.mulWadUp(rate).mulWadUp(EPOCHS_IN_DAY);
        // compute DTI - divWadUp here adds the extra WAD back to compare with DTI level in storage
        return dailyRate.divWadUp(weightedEDR);
    }

    /// @dev compute the DTE
    function computeDTE(
        uint256 principal,
        uint256 agentTotalValue
    ) public pure returns (uint256) {
        // since agentTotalValue includes borrowed funds (principal),
        // agentTotalValue should always be greater than principal
        // however, this could happen if the agent is severely slashed over long durations
        // in this case, they're definitely over the maxDTE, regardless of what it's set to
        if (agentTotalValue <= principal) return type(uint256).max;
        // return DTE
        return principal.divWadDown(agentTotalValue - principal);
    }

    /// @dev _getRate returns the rate with an extra WAD factor for precision
    function _getRate(uint256 gcred) internal view returns (uint256) {
        // since GCRED is between 40-100, we subtract 39 to get the index in the rateArray
        return baseRate.mulWadUp(rateLookup[gcred - minGCRED]);
    }
}
