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

    VCVerifier vcVerifier = new VCVerifier("glif.io", "1");
    address issuer = vm.addr(privateKey);

    MinerData memory miner = MinerData(1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, 10e18, 5e18, 0, 0);

    VerifiableCredential memory vc = VerifiableCredential(
      issuer,
      makeAddr("SUBJECT"),
      block.number,
      block.number + 100,
      miner
    );

    bytes32 digest = vcVerifier.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

    assertEq(vcVerifier.recover(vc, v, r, s), issuer);
  }

  function testVerifyCredentialFromJavaScript() private {
    uint8 v = 28;
    bytes32 r = hex"3b43bdb9918247ce43a6f85feda05a7a28042991febb87dc36c75fc940d9241b";
    bytes32 s = hex"39d6c763bf4d2d7d4c76a29d2395af9d7d9df1b49c14899fec98ea0149294f29";
    VCVerifier vcVerifier = new VCVerifier("glif.io", "1");

    MinerData memory miner = MinerData(100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100);

    VerifiableCredential memory vc = VerifiableCredential(
      0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
      0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
      100,
      100,
      miner
    );

    console.log("ADDRESS", address(vcVerifier));

    assertEq(vcVerifier.recover(vc, v, r, s), 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
  }
}
