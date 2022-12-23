// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {ROLE_VC_ISSUER} from "src/Constants/Roles.sol";
import {MinerData, VerifiableCredential} from "src/Types/Structs/Credentials.sol";

abstract contract VCVerifier is RouterAware, EIP712 {
  constructor(string memory _name, string memory _version)
    EIP712(_name, _version) {}

  string internal constant _VERIFIABLE_CREDENTIAL_TYPE =
    "VerifiableCredential(address issuer,address subject,uint256 epochIssued,uint256 epochValidUntil,MinerData miner)";
  string internal constant _MINER_DATA_TYPE =
    "MinerData(uint256 assets,uint256 expectedDailyRewards,uint256 exposureAtDefault,uint256 expectedLoss,uint256 liabilities,uint256 liquidationValue,uint256 lossGivenDefault,uint256 probabilityOfDefault,uint256 qaPower,uint256 rawPower,uint256 startEpoch,uint256 unexpectedLoss)";

  bytes32 public constant _VERIFIABLE_CREDENTIAL_TYPE_HASH =
    keccak256(abi.encodePacked(_VERIFIABLE_CREDENTIAL_TYPE, _MINER_DATA_TYPE));

  bytes32 public constant _MINER_DATA_TYPE_HASH =
    keccak256(abi.encodePacked(_MINER_DATA_TYPE));

  uint256 latestVCEpochIssued;

  modifier isValidVC(VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) {
    require(isValid(vc, v, r, s), "Invalid VC");
    latestVCEpochIssued = vc.epochIssued;
    _;
  }

  function deriveMinerDataHash(MinerData memory miner) public pure returns(bytes32) {
    return keccak256(abi.encode(
      _MINER_DATA_TYPE_HASH,
      miner.assets,
      miner.expectedDailyRewards,
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
    VerifiableCredential memory vc
  ) public view returns(bytes32) {
      return _hashTypedDataV4(deriveStructHash(vc));
  }

  function recover(
    VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s
  ) public view returns (address) {
      return ECDSA.recover(digest(vc), v, r, s);
  }

  function isValid(
    VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s
  ) public view returns (bool) {
    address issuer = recover(vc, v, r, s);
    require(issuer == vc.issuer, "VCVerifier: Mismatching issuer");
    require(isValidIssuer(issuer), "VCVerifier: VC issued by unknown issuer");
    // TODO: Verify this check is not needed - if another agent tried to use a credential, the recovered issuer would come back wrong
    require(vc.subject == address(this), "VCVerifier: VC not issued to this contract");
    require(block.number >= vc.epochIssued && block.number <= vc.epochValidUntil, "Verifiable Credential not in valid epoch range");
    require(vc.epochIssued > latestVCEpochIssued, "VCVerifier: VC issued in the past");

    return true;
  }

  function isValidIssuer(address issuer) internal view returns (bool) {
    return IMultiRolesAuthority(
      address(RoleAuthority.getSubAuthority(router, address(this)))
    ).doesUserHaveRole(issuer, ROLE_VC_ISSUER);
  }
}
