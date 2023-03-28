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
   * @dev The lowest interest rate that the protocol will charge
   *
   * This rate is computed dynamically based off the network's inflation rate
   */
  uint256 baseRate;
  uint256 collateralValue;
  uint256 expectedDailyFaultPenalties;
  uint256 expectedDailyRewards;
  uint256 gcred;
  uint256 lockedFunds;
  uint256 qaPower;
  uint256 principal;
  uint256 startEpoch;
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

  function getBaseRate(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getBaseRate(vc.claim);
  }

  function getAgentValue(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getAgentValue(vc.claim);
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
}
