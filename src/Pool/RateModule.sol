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

/**
 * @title RateModule
 * @author GLIF
 * @notice RateModule is a contract that the Infinity Pool outsource's its financial math related to getting rates and approving borrow requests
 *
 * The primary responsibility of this contract is the `isApproved` function, which is used to determine whether an Agent is in "good standing". An Agent is in good standing if:

 */
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

    /// @dev `router` is the cached router address
    address internal immutable router;

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
     * @param vc - the Agent's verifiable credential
     * @return rate - the rate for the Agent's current position within the Pool
     * @dev getRate returns a per epoch rate with an additional WAD for precision
     */
    function getRate(
        VerifiableCredential calldata vc
    ) external view returns (uint256 rate) {
        return _getRate(vc.getGCRED(credParser));
    }

    /// @dev penaltyRate returns the rate for the worst GCRED which is used in liquidations
    function penaltyRate() external view returns (uint256 rate) {
        return _getRate(minGCRED);
    }

    /**
     * @notice isApproved returns false if the Agent is in a bad state (over leveraged, not on whitelist..etc)
     * @param account - the Agent's account with the Infinity Pool
     * @param vc - the Agent's verifiable credential.
     * @dev the VC's statistics are post-processed - they report the information of an Agent as if the associated action had just executed. For example, if an Agent is attempting to borrow, the VC will report the Agent's new principal as if the Agent had just borrowed.
     *
     * @dev isApproved returns true if all of the following conditions are met:
     * 1. The Agent is not more than `defaultWindow` epochs behind on payments. This ensure that a SP can't lag too far behind on payments.
     * 2. The Agent's total principal is less than or equal to the maximum principal for their level. This is primarily a safety mechanism to ensure the Pool can roll-out in a well diversified way. It also allows the pool to toggle between more/less KYC type checks to allow Agents to increase the amount they can borrow.
     * 3. The Agent's principal divided by its collateral value (LTV ratio) must be less than `maxLTV`. This check exists to ensure that the pool can recover its funds in the event of a liquidation.
     * 4. The Agent's principal divided by its equity (DTE ratio) must be less than `maxDTE`. This check exists to ensure that the Agent has sufficient skin in the game and is not incentivized to walk away from their Agent and SPs.
     * 5. The Agent's expected daily interest payments divided by its expected daily rewards must be less than `maxDTI`. This check exists to ensure that a SP can meet its expected payments solely from its block rewards.
     *
     */
    function isApproved(
        Account calldata account,
        VerifiableCredential calldata vc
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
        // checks for zero to avoid dividing or multiplying by zero downstream
        // if you have nothing borrowed, you're good no matter what
        if (totalPrincipal == 0) return true;
        // if you have bad GCRED, you're not approved
        uint256 gcred = vc.getGCRED(credParser);
        if (gcred < minGCRED) return false;
        // if you have no collateral, it's an automatic no
        uint256 collateralValue = vc.getCollateralValue(credParser);
        if (collateralValue == 0) return false;

        // if LTV is greater than `maxLTV`, Agent is undercollateralized
        if (computeLTV(totalPrincipal, collateralValue) > maxLTV) {
            return false;
        }
        // if DTE is greater than `maxDTE`, Agent does not have sufficient skin in the game
        if (computeDTE(totalPrincipal, vc.getAgentValue(credParser)) > maxDTE) {
            return false;
        }

        // if DTI is greater than `maxDTI`, Agent cannot meet its payments solely from block rewards
        return computeDTI(
            vc.getExpectedDailyRewards(credParser),
            _getRate(gcred),
            account.principal,
            totalPrincipal
        ) <= maxDTI;
    }

    /// @dev sets the max DTI score to be considered approved
    function setMaxDTI(uint256 _maxDTI) external onlyOwner {
        maxDTI = _maxDTI;
    }
    /// @dev sets the max DTE score to be considered approved
    function setMaxDTE(uint256 _maxDTE) external onlyOwner {
        maxDTE = _maxDTE;
    }
    /// @dev sets the max LTV to be considered approved
    function setMaxLTV(uint256 _maxLTV) external onlyOwner {
        maxLTV = _maxLTV;
    }
    /// @dev sets the min GCRED score to be considered approved
    function setMinGCRED(uint256 _minGCRED) external onlyOwner {
        minGCRED = _minGCRED;
    }
    /// @dev sets the base rate
    function setBaseRate(uint256 _baseRate) external onlyOwner {
        baseRate = _baseRate;
    }
    /// @dev sets the rate lookup table. The rateLookup table is a table of perEpoch rate multipliers that get mulWad'd with the base rate to get the final rate
    function setRateLookup(uint256[61] calldata _rateLookup) external onlyOwner {
        rateLookup = _rateLookup;
    }
    /// @dev sets the credentialParser in case we need to update a data type
    function updateCredParser() external onlyOwner {
        credParser = address(GetRoute.credParser(router));
    }
    /// @dev sets the array of max borrow amounts for each level
    function setLevels(uint256[10] calldata _levels) external onlyOwner {
        levels = _levels;
    }
    /// @dev sets the array of max borrow amounts for each level
    function setAgentLevels(uint256[] calldata agentIDs, uint256[] calldata level) external onlyOwner {
        if (agentIDs.length != level.length) revert InvalidParams();
        uint256 i = 0;
        for (; i < agentIDs.length; i++) {
          accountLevel[agentIDs[i]] = level[i];
        }
    }

    /**
     * @notice computeLTV computes the principal to collateral value ratio
     * @param principal - the total principal of the Agent
     * @param collateralValue - the total collateral value of the Agent
     * @dev collateral value is computed on the server as: vesting funds + (locked funds * termination risk discount)
     */
    function computeLTV(
        uint256 principal,
        uint256 collateralValue
    ) public pure returns (uint256) {
        return principal.divWadDown(collateralValue);
    }

    /**
     * @notice computeDTI computes the principal to expectedDailyRewards ratio
     * @param expectedDailyRewards - the total principal of the Agent
     * @param rate - the per epoch rate of the Agent given the GCRED score
     * @param accountPrincipal - the total principal borrowed from the infinity pool
     * @param totalPrincipal - the total principal borrowed from all pools
     * @dev the DTI is weighted by the Agent's borrow amount from the pool relative to any other pools
     * @dev the rate is WAD based
     */
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

    /**
     * @notice computeDTE computes the principal to equity value ratio
     * @param principal - the total principal of the Agent
     * @param agentTotalValue - the total value of the Agent
     * @dev agent total value includes principal borrowed by the Agent
     */
    function computeDTE(
        uint256 principal,
        uint256 agentTotalValue
    ) public pure returns (uint256) {
        // since agentTotalValue includes borrowed funds (principal),
        // agentTotalValue should always be greater than principal
        // however, this assumption could break if the agent is severely slashed over long durations
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
