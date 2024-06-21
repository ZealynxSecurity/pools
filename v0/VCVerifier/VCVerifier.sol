// SPDX-License-Identifier: UNLICENSED
// solhint-disable
pragma solidity ^0.8.17;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AuthController} from "v0/Auth/AuthController.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {ROUTE_VC_ISSUER} from "v0/Constants/Routes.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "v0/Types/Interfaces/IVCVerifier.sol";

/**
 * @title VCVerifier
 * @author GLIF
 * @notice Responsible for validating EIP712 signed data blobs of W3C inspired Verifiable Credentials
 * @dev Each credential must be signed by the known VC Issuer and corresponds to an `action` being taken by a particular agent `subject`
 * @dev Each credential can only be used once, see Agent Police for more details
 */
abstract contract VCVerifier is IVCVerifier, EIP712 {
    error InvalidCredential();

    address internal immutable router;

    constructor(string memory _name, string memory _version, address _router) EIP712(_name, _version) {
        router = _router;
    }

    string internal constant _VERIFIABLE_CREDENTIAL_TYPE =
        "VerifiableCredential(address issuer,uint256 subject,uint256 epochIssued,uint256 epochValidUntil,uint256 value,bytes4 action,uint64 target,bytes claim)";

    bytes32 public constant _VERIFIABLE_CREDENTIAL_TYPE_HASH = keccak256(abi.encodePacked(_VERIFIABLE_CREDENTIAL_TYPE));

    function deriveStructHash(VerifiableCredential memory vc) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _VERIFIABLE_CREDENTIAL_TYPE_HASH,
                vc.issuer,
                vc.subject,
                vc.epochIssued,
                vc.epochValidUntil,
                vc.value,
                vc.action,
                vc.target,
                keccak256(abi.encodePacked(vc.claim))
            )
        );
    }

    function digest(VerifiableCredential memory vc) public view returns (bytes32) {
        return _hashTypedDataV4(deriveStructHash(vc));
    }

    function recover(SignedCredential memory sc) public view returns (address) {
        return ECDSA.recover(digest(sc.vc), sc.v, sc.r, sc.s);
    }

    function validateCred(uint256 agent, bytes4 selector, SignedCredential memory sc) public view {
        address issuer = recover(sc);
        if (
            issuer != sc.vc.issuer || !isValidIssuer(issuer) || sc.vc.subject != agent || sc.vc.action != selector
                || !(block.number >= sc.vc.epochIssued && block.number <= sc.vc.epochValidUntil) || sc.vc.subject == 0
        ) revert InvalidCredential();
    }

    function isValidIssuer(address issuer) internal view returns (bool) {
        return IRouter(router).getRoute(ROUTE_VC_ISSUER) == issuer;
    }
}
