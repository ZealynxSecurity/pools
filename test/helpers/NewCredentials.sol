// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import {INewCredentials} from "test/helpers/INewCredentials.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
struct NewAgentData {
  /**
   * @dev The total value of the Agent's assets
   * This encompasses:
   * - The liquid funds (WFIL + FIL) in the Agent contract
   * - The vesting + locked + available funds in each of the Agent's miners
   *
   * Note that available funds on the Agent's miners are discounted by the Agent's collateralization ratio because they can get re-pledged without the protocol knowing
   */
  uint256 agentValue;
  /**
   * @dev collateralValue is computed as vesting funds + locked funds - termination fees
   * This does not include available funds on the Agent or any of its miners - it incentivizes miners to pledge their available balances
   */
  uint256 collateralValue;
  /**
   * @dev The daily fee for sector fault penalties for any of the Agent's faulty sectors
   */
  uint256 expectedDailyFaultPenalties;
  /**
   * @dev The aggregated block rewards expected to be earned by this Agent's miners in the next 24h
   */
  uint256 expectedDailyRewards;
  /**
   * @dev A numerical representation of the Agent's financial risk
   * GCRED is used as an index in the rateArray in the rateModule, such that it applies a per epoch multiplier to the base rate
   */
  uint256 gcred;
  /**
   * @dev The total amount of vesting funds + initial pledge collateral aggregated across all of the Agent's miners
   */
  uint256 lockedFunds;
  /**
   * @dev The aggregated quality adjusted power of all of the Agent's miners
   */
  uint256 qaPower;
  /**
   * @dev The total amount of FIL borrowed by the Agent
   */
  uint256 principal;
  /**
   * @dev The epoch in which the Agent started borrowing FIL
   */
  uint256 startEpoch;

  uint256 newVariable;
}


struct SignedCredential {
  VerifiableCredential vc;
  uint8 v;
  bytes32 r;
  bytes32 s;
}

library NewCredentials {
  function parseClaim(
    VerifiableCredential memory vc
  ) internal pure returns (NewAgentData memory agentData) {
    agentData = abi.decode(vc.claim, (NewAgentData));
  }

  function getAgentValue(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getAgentValue(vc.claim);
  }

  function getCollateralValue(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getCollateralValue(vc.claim);
  }

  function getGCRED(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getGCRED(vc.claim);
  }

  function getQAPower(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getQAPower(vc.claim);
  }

  function getExpectedDailyRewards(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getExpectedDailyRewards(vc.claim);
  }

  function getPrincipal(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getPrincipal(vc.claim);
  }

  function getLockedFunds(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getLockedFunds(vc.claim);
  }
  
  function getNewVariable(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return INewCredentials(credParser).getNewVariable(vc.claim);
  }
}
