// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {MinerData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {ROUTE_VC_ISSUER} from "src/Constants/Routes.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";

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

  // TODO: Use error library
  function isValid(
    address agent,
    VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s
  ) public view returns (bool) {
    address issuer = recover(vc, v, r, s);
    require(issuer == vc.issuer, "VCVerifier: Not authorized");
    require(isValidIssuer(issuer), "VCVerifier: Not authorized");
    require(vc.subject == agent, "VCVerifier: Not authorized");
    require(block.number >= vc.epochIssued && block.number <= vc.epochValidUntil, "Verifiable Credential not in valid epoch range");

    return true;
  }

  function isValidIssuer(address issuer) internal view returns (bool) {
    return IRouter(router).getRoute(ROUTE_VC_ISSUER) == issuer;
  }

  function _isValidVC(address agent, SignedCredential memory signedCredential) internal view returns (bool) {
    require(isValid(
      agent,
      signedCredential.vc,
      signedCredential.v,
      signedCredential.r,
      signedCredential.s
    ), "Invalid VC");

    return true;
  }
}
