// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "src/Router/RouterAware.sol";

struct MinerData {
  bytes32 additional;
  uint256 assets;
  uint256 exposureAtDefault;
  uint256 expectedLoss;
  uint256 liabilities;
  uint256 liquidationValue;
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
  MinerData miner;
}

contract VCVerifier is RouterAware, EIP712 {
  mapping(address => bool) public validIssuers;

  constructor(string memory _name, string memory _version)
    EIP712(_name, _version) {}

  string internal constant _VERIFIABLE_CREDENTIAL_TYPE =
    "VerifiableCredential(address issuer,address subject,uint256 epochIssued,uint256 epochValidUntil,MinerData miner)";
  string internal constant _MINER_DATA_TYPE =
    "MinerData(bytes32 additional,uint256 assets,uint256 exposureAtDefault,uint256 expectedLoss,uint256 liabilities,uint256 liquidationValue,uint256 lossGivenDefault,uint256 probabilityOfDefault,uint256 qaPower,uint256 rawPower,uint256 startEpoch,uint256 unexpectedLoss)";

  bytes32 public constant _VERIFIABLE_CREDENTIAL_TYPE_HASH =
    keccak256(abi.encodePacked(_VERIFIABLE_CREDENTIAL_TYPE, _MINER_DATA_TYPE));

  bytes32 public constant _MINER_DATA_TYPE_HASH =
    keccak256(abi.encodePacked(_MINER_DATA_TYPE));

  function deriveMinerDataHash(MinerData memory miner) public pure returns(bytes32) {
    return keccak256(abi.encode(
      _MINER_DATA_TYPE_HASH,
      miner.additional,
      miner.assets,
      miner.exposureAtDefault,
      miner.expectedLoss,
      miner.liabilities,
      miner.liquidationValue,
      miner.lossGivenDefault,
      miner.probabilityOfDefault,
      miner.qaPower,
      miner.rawPower,
      miner.startEpoch,
      miner.unexpectedLoss
    ));
  }

  function deriveStructHash(VerifiableCredential memory vc) public pure returns(bytes32) {
    return keccak256(abi.encode(
      _VERIFIABLE_CREDENTIAL_TYPE_HASH,
      vc.issuer,
      vc.subject,
      vc.epochIssued,
      vc.epochValidUntil,
      deriveMinerDataHash(vc.miner)
    ));
  }

  function digest(
    VerifiableCredential memory vc) public view returns(bytes32) {
      return _hashTypedDataV4(deriveStructHash(vc));
  }

  function recover(
    VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) public view returns (address) {
      return ECDSA.recover(digest(vc), v, r, s);
  }

  function isValid(VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
    address issuer = recover(vc, v, r, s);
    require(validIssuers[issuer], "Verifiable Credential issued by unknown issuer");
    require(issuer == vc.issuer, "Mismatching issuer");
    require(block.number >= vc.epochIssued && block.number <= vc.epochValidUntil, "Verifiable Credential not in valid epoch range");

    return true;
  }
}
