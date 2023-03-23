// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {Operatable} from "src/Auth/Operatable.sol";
import {RouterAware} from "src/Router/RouterAware.sol";

import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {ROUTE_CRED_PARSER} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

contract RateModule is IRateModule, Operatable, RouterAware {

    using Credentials for VerifiableCredential;

    uint256 constant WAD = 1e18;

    /// @dev `maxDTI` is the maximum ratio of expected daily interest payments to expected daily rewards (1)
    uint256 private maxDTI = 0.5e18;

    /// @dev `maxLTV` is the maximum ratio of principal to collateral
    uint256 private maxLTV = 0.95e18;

    /// @dev `rateLookup` is a memoized GCRED => rateMultiplier lookup table. It sets the interest curve
    uint256[100] private rateLookup;

    /// @dev `credParser` is the cached cred parser
    address public credParser;

    constructor(
        address _owner,
        address _operator,
        address _router,
        uint256[100] memory _rateLookup
    ) Operatable(_owner, _operator) {
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
      return (vc.getBaseRate(credParser) * rateLookup[vc.getGCRED(credParser)]) / WAD;
    }

    /**
     * @notice isOverLeveraged returns true if the Agent is over leveraged
     * In this version, an Agent can be over-leveraged in either of two cases:
     * 1. The Agent's principal is more than the equity weighted `agentTotalValue`
     * 2. The Agent's expected daily payment is more than `dtiWeight` of their income
     *
     * NOTE: (KP): I would recommend just evaluating if poolShareOfValue > accountPrincipal it's functionally the same
     */
    function isOverLeveraged(
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (bool) {
        // equity percentage
        uint256 totalPrincipal = vc.getPrincipal(credParser);
        // the pool's record of what the agent borrowed from the pool
        uint256 accountPrincipal = account.principal;
        // compute our pool's percentage of the agent's assets, in WAD math
        uint256 equityPercentage = (accountPrincipal * WAD) / totalPrincipal;
        // If this pool has no equity in the agent, they are not over leveraged
        if(equityPercentage == 0) return false;
        // available balance + locked funds + vesting funds
        uint256 agentTotalValue = vc.getAgentValue(credParser);
        // compute value used in LTV calculation
        // We leave the e18 in here so we don't have to add it back in when calculating LTV
        // If the agent's principal is greater than the value of their assets, they are over leveraged
        if(accountPrincipal > agentTotalValue) return true;
        // compute the amount of agent equity that this pool can count on
        uint256 poolShareOfValue = (equityPercentage * (agentTotalValue - accountPrincipal)) / WAD;
        // if (poolShareOfValue < accountPrincipal) return true;
        // compute LTV (also wrong bc %)
        uint256 ltv = accountPrincipal * WAD / poolShareOfValue;
        // if LTV is greater than `maxLTV` (e18 denominated), we are over leveraged (can't mortgage more than the value of your home)
        if (ltv > WAD) return true;
        // compute the rate based on the gcred
        uint256 rate = getRate(account, vc);
        // compute expected daily payments to align with expected daily reward
        uint256 dailyRate = (rate * EPOCHS_IN_DAY * accountPrincipal) / WAD;
        // compute DTI
        uint256 dti = dailyRate * WAD / vc.getExpectedDailyRewards(credParser);

        return dti > maxDTI;
    }

    function setMaxDTI(uint256 _maxDTI) external onlyOwnerOperator {
        maxDTI = _maxDTI;
    }

    function setMaxLTV(uint256 _maxLTV) external onlyOwnerOperator {
        maxLTV = _maxLTV;
    }

    function setRateLookup(uint256[100] memory _rateLookup) external onlyOwnerOperator {
        rateLookup = _rateLookup;
    }

    function updateCredParser() external onlyOwnerOperator {
        credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    }
}
