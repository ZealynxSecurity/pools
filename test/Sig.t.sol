// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "bytes-utils/BytesLib.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {FlipSig} from "./helpers/FlipSig.sol";

contract SigReplay is Test {
    // this test illustrates signature malleability and the need for replay protection in the Agent Police
    function testReplayNativeRecover(
        uint256 vcIssuerPk,
        bytes32 digest
    ) public {
        (
            address signer,
            uint8 v,
            bytes32 r,
            bytes32 s
        ) = generateSignatureAndAddress(vcIssuerPk, digest);

        FlipSig flipSig = new FlipSig();

        address signer2 = recoverSignerUnsafe(v, r, s, digest);

        (uint8 v_, bytes32 r_, bytes32 s_) = flipSig.reuseSignature(v, r, s);

        address signer3 = recoverSignerUnsafe(v, r, s, digest);

        assertTrue(signer == signer2, "Signature must recover properly");
        // !
        assertTrue(
            signer == signer3,
            "Illustrate: two different signatures recover to same address"
        );
        // !
        assertTrue(
            !BytesLib.equal(abi.encode(v, r, s), abi.encode(v_, r_, s_)),
            "Illustrate: two different signatures create same hash key"
        );
    }

    // this test illustrates how OZ libraries prevent signature malleability
    function testReplayOZRecover(uint256 vcIssuerPk, bytes32 digest) public {
        FlipSig flipSig = new FlipSig();

        (
            address signer,
            uint8 v,
            bytes32 r,
            bytes32 s
        ) = generateSignatureAndAddress(vcIssuerPk, digest);

        address signer2 = ECDSA.recover(digest, v, r, s);

        (uint8 v_, bytes32 r_, bytes32 s_) = flipSig.reuseSignature(v, r, s);

        vm.expectRevert();
        address signer3 = ECDSA.recover(digest, v_, r_, s_);

        assertTrue(signer == signer2, "Signature must recover properly");
        assertTrue(
            signer != signer3,
            "Illustrate: two different signatures recover to same address"
        );
        assertTrue(
            !BytesLib.equal(abi.encode(v, r, s), abi.encode(v_, r_, s_)),
            "Illustrate: two different signatures create same hash key"
        );
    }

    function generateSignatureAndAddress(
        uint256 vcIssuerPk,
        bytes32 digest
    ) internal returns (address signer, uint8 v, bytes32 r, bytes32 s) {
        vcIssuerPk = bound(
            vcIssuerPk,
            1,
            115792089237316195423570985008687907852837564279074904382605163141518161494336
        );

        signer = vm.addr(vcIssuerPk);

        (v, r, s) = vm.sign(vcIssuerPk, digest);
    }

    function recoverSignerUnsafe(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 _hash
    ) internal pure returns (address signer_) {
        signer_ = ecrecover(_hash, v, r, s);
    }
}
