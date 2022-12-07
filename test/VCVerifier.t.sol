// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/VCVerifier/VCVerifier.sol";

contract VCVerifierTest is Test {
  function testVerifyCredential(uint256 privateKey) public {
    // here we fuzz with a bunch of private keys
    // sometimes the signing fails if the private key is too large, so we bound its size
    privateKey = bound(privateKey, 1, 1e36);
    require(privateKey >= 1 && privateKey <= 1e36);

    VCVerifier vcVerifier = new VCVerifier("lending.glif.io", "1");
    address issuer = vm.addr(privateKey);
    address subject = makeAddr("SUBJECT");
    uint256 epochIssued = block.number;
    uint256 epochValidUntil = block.number + 100;

    MinerData memory miner = MinerData(
      block.number,
      0,
      0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      issuer,
      subject,
      epochIssued,
      epochValidUntil,
      miner
    );

    bytes32 digest = vcVerifier.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    assertEq(vcVerifier.recover(vc, v, r, s), issuer);
  }
}
