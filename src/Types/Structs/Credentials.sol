// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import {ICredentials} from "src/Types/Interfaces/ICredentials.sol";

struct AgentData {
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
   * @dev The aggregated quality adjusted power of all of the Agent's miners
   */
  uint256 qaPower;
  /**
   * @dev The total amount of FIL borrowed by the Agent
   */
  uint256 principal;
  /**
   * @dev The total amount of faulty sectors summed up across all the Agent's miners
   */
  uint256 faultySectors;
  /**
   * @dev The total amount of live sectors summed up across all the Agent's miners
   */
  uint256 liveSectors;
  /**
   * @dev An energy efficiency score computed by the Filecoin Green API
   */
  uint256 greenScore;
}

struct VerifiableCredential {
  /**
   * @dev The issuer of the credential
   * Must be a valid VC Issuer recognized by the Router
   */
  address issuer;
  /**
   * @dev The id of the agent to which the credential is issued
   */
  uint256 subject;
  /**
   * @dev The epoch in which the credential was signed and issued
   */
  uint256 epochIssued;
  /**
   * @dev The epoch in which the credential expires
   * Approximately a 30 minute period of epochs
   */
  uint256 epochValidUntil;
  /**
   * @dev The value change associated with the action
   */
  uint256 value;
  /**
   * @dev The action associated with the credential
   * Actions must correspond to the `msg.sig` of the function where the credential is used
   */
  bytes4 action;
  /**
   * @dev The miner ID that is the target of the action
   * Not all actions require a target - for instance, borrow does not require a target, since the borrower is the Agent and not a specific miner
   *
   * An action like pullFundsFromMiner requires a target, since the Agent is not the miner where funds are being pulled
   */
  uint64 target;
  /**
   * @dev The bytes representation of `AgentData`
   */
  bytes claim;
}

struct SignedCredential {
  VerifiableCredential vc;
  uint8 v;
  bytes32 r;
  bytes32 s;
}

library Credentials {
  function parseClaim(
    VerifiableCredential memory vc
  ) internal pure returns (AgentData memory agentData) {
    agentData = abi.decode(vc.claim, (AgentData));
  }

  function getAgentValue(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getAgentValue(vc.claim);
  }

  function getCollateralValue(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getCollateralValue(vc.claim);
  }

  function getGCRED(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getGCRED(vc.claim);
  }

  function getQAPower(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getQAPower(vc.claim);
  }

  function getExpectedDailyRewards(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getExpectedDailyRewards(vc.claim);
  }

  function getPrincipal(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getPrincipal(vc.claim);
  }

  function getLockedFunds(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getLockedFunds(vc.claim);
  }

  function getGreenScore(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getGreenScore(vc.claim);
  }

  function getFaultySectors(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getFaultySectors(vc.claim);
  }

  function getLiveSectors(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getLiveSectors(vc.claim);
  }
}
