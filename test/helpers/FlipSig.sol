// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

contract FlipSig {
    function reuseSignature(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external pure returns (uint8 v_, bytes32 r_, bytes32 s_) {
        // Flipped signature values.
        bytes32 flippedS;
        uint8 flippedV;

        assembly {
            // Flip S.
            flippedS := sub(
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141,
                s
            )

            // Flip V.
            flippedV := add(eq(v, 27), 27)
        }

        // Return new signature.
        return (flippedV, r, flippedS);
    }
}
