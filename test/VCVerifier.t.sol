// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {MultiRolesAuthority, RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {Authority} from "src/Auth/Auth.sol";
import {ROLE_VC_ISSUER} from "src/Constants/Roles.sol";
import "src/VCVerifier/VCVerifier.sol";
import "./BaseTest.sol";

contract VCVerifierMock is VCVerifier {
  function _cacheLastValidEpoch(uint256 epoch) public {
    latestVCEpochIssued = epoch;
  }

  constructor(
    address _router,
    string memory verifiedName,
    string memory verifiedVersion
  ) VCVerifier(verifiedName, verifiedVersion) {
    router = _router;
  }
}

contract VCVerifierTest is BaseTest {
  VCVerifierMock public vcv;
  MultiRolesAuthority public sauth;

  function setUp() public {
    vcv = new VCVerifierMock(address(router), "glif.io", "1");
    sauth = RoleAuthority.newMultiRolesAuthority(address(this), Authority(address(0)));
    sauth.setUserRole(address(vcIssuer), ROLE_VC_ISSUER, true);
    RoleAuthority.setSubAuthority(address(router), address(vcv), sauth);
  }

  function testVerifyCredential() public {
    (
      VerifiableCredential memory vc,
      uint8 v, bytes32 r, bytes32 s
    ) = issueGenericVC(address(vcv));

    assertTrue(vcv.isValid(vc, v, r, s));
  }

  function testVerifyCredentialFromWrongIssuer() public {
    uint256 qaPower = 10e10;

    MinerData memory miner = MinerData(
      1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      address(vcv),
      block.number,
      block.number + 100,
      miner
    );

    bytes32 digest = IVCVerifier(vc.subject).digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest);
    vm.expectRevert("VCVerifier: Mismatching issuer");
    vcv.isValid(vc, v, r, s);
  }

  function testBadIssuer() public {
    VCVerifierMock vcv2 = new VCVerifierMock(address(router), "glif.io", "1");
    MultiRolesAuthority auth = RoleAuthority.newMultiRolesAuthority(address(this), Authority(address(0)));
    RoleAuthority.setSubAuthority(address(router), address(vcv2), auth);

    uint256 qaPower = 10e10;

    MinerData memory miner = MinerData(
      1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      address(vcv2),
      block.number,
      block.number + 100,
      miner
    );

    bytes32 digest = IVCVerifier(vc.subject).digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
    vm.expectRevert("VCVerifier: VC issued by unknown issuer");
    vcv2.isValid(vc, v, r, s);
  }

  function testFalseSubject() public {
    (
      VerifiableCredential memory vc,
      uint8 v, bytes32 r, bytes32 s
    ) = issueGenericVC(address(vcv));

    vc.subject = makeAddr("FALSE_SUBJECT");
    // NOTE - this test fails with "mismatching issuer"
    // because ECRecover won't recover the right result with the wrong subject
    vm.expectRevert("VCVerifier: Mismatching issuer");
    vcv.isValid(vc, v, r, s);
  }

  function testIsValidWithStaleVC() public {
    (
      VerifiableCredential memory vc,
      uint8 v, bytes32 r, bytes32 s
    ) = issueGenericVC(address(vcv));

    // fast foward time to issue a new vc that gets cached
    vm.roll(block.number + 100);

    (
      VerifiableCredential memory newVC,,,
    ) = issueGenericVC(address(vcv));
    vcv._cacheLastValidEpoch(newVC.epochIssued);

    vm.expectRevert("VCVerifier: VC issued in the past");
    vcv.isValid(vc, v, r, s);
  }
}
