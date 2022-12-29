// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

struct MinerData {
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
  MinerData miner;
}

struct SignedCredential {
  VerifiableCredential vc;
  uint8 v;
  bytes32 r;
  bytes32 s;
}
