// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {ROUTE_VC_ISSUER} from "src/Constants/Routes.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";

abstract contract VCVerifier is RouterAware, EIP712 {
  error InvalidCredential();

  constructor(string memory _name, string memory _version)
    EIP712(_name, _version) {}

  string internal constant _VERIFIABLE_CREDENTIAL_TYPE =
    "VerifiableCredential(address issuer,address subject,uint256 epochIssued,uint256 epochValidUntil,uint256 cap,AgentData miner)";
  string internal constant _MINER_DATA_TYPE =
    "AgentData(uint256 assets,uint256 expectedDailyRewards,uint256 exposureAtDefault,uint256 expectedLoss,uint256 liabilities,uint256 lossGivenDefault,uint256 probabilityOfDefault,uint256 qaPower,uint256 rawPower,uint256 startEpoch,uint256 unexpectedLoss)";

  bytes32 public constant _VERIFIABLE_CREDENTIAL_TYPE_HASH =
    keccak256(abi.encodePacked(_VERIFIABLE_CREDENTIAL_TYPE, _MINER_DATA_TYPE));

  bytes32 public constant _MINER_DATA_TYPE_HASH =
    keccak256(abi.encodePacked(_MINER_DATA_TYPE));

  function deriveStructHash(VerifiableCredential memory vc) public pure returns(bytes32) {
    return keccak256(abi.encode(
      _VERIFIABLE_CREDENTIAL_TYPE_HASH,
      vc.issuer,
      vc.subject,
      vc.epochIssued,
      vc.epochValidUntil,
      vc.value,
      vc.claim
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

  function validateCred(
    uint256 agent,
    VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s
  ) public view {
    address issuer = recover(vc, v, r, s);
    if (
      issuer != vc.issuer ||
      !isValidIssuer(issuer) ||
      vc.subject != agent ||
      !(
        block.number >= vc.epochIssued &&
        block.number <= vc.epochValidUntil
      )
    ) revert InvalidCredential();
  }

  function isValidIssuer(address issuer) internal view returns (bool) {
    return IRouter(router).getRoute(ROUTE_VC_ISSUER) == issuer;
  }
}
