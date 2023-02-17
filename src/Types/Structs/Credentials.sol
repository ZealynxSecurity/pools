// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;
import {ICredentials} from "src/Types/Interfaces/ICredentials.sol";
struct AgentData {
  uint256 assets;
  uint256 expectedDailyRewards;
  uint256 exposureAtDefault;
  uint256 expectedLoss;
  uint256 liabilities;
  uint256 lossGivenDefault;
  uint256 probabilityOfDefault;
  uint256 qaPower;
  uint256 rawPower;
  uint256 startEpoch;
  uint256 unexpectedLoss;
}

struct VerifiableCredential {
  address issuer;
  address subject;
  uint256 epochIssued;
  uint256 epochValidUntil;
  uint256 cap;
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

  function getAssets(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getAssets(vc.claim);
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
  function getLiabilities(
    VerifiableCredential memory vc,
    address credParser
  ) internal pure returns (uint256) {
    return ICredentials(credParser).getLiabilities(vc.claim);
  }
}
