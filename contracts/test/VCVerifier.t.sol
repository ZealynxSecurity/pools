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

  function testVerifyCredentialFromJavaScript() public {
    uint8 v = 28;
    bytes32 r = hex"695999696dfda891d03c90a24031db91bafedc351a1e87a32d18f929c082e807";
    bytes32 s = hex"0f95bddf9f19515e708e4540d2bf0ee1b12fbec3c03a2373b319720545a09a22";
    VCVerifier vcVerifier = new VCVerifier("lending.glif.io", "1");

    address issuer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address subject = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 epochIssued = 100;
    uint256 epochValidUntil = 100;

    MinerData memory miner = MinerData(
      100,
      100,
      100
    );


    VerifiableCredential memory vc = VerifiableCredential(
      issuer,
      subject,
      epochIssued,
      epochValidUntil,
      miner
    );

    console.logBytes32(vcVerifier.deriveStructHash(vc));

    assertEq(vcVerifier.recover(vc, v, r, s), 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
  }
}
