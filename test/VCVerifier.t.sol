// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AuthController} from "src/Auth/AuthController.sol";
import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {Authority} from "src/Auth/Auth.sol";
import "src/VCVerifier/VCVerifier.sol";
import "./BaseTest.sol";

contract VCVerifierMock is VCVerifier {
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
  address public agent = makeAddr("AGENT");

  function setUp() public {
    vcv = new VCVerifierMock(address(router), "glif.io", "1");
    sauth = AuthController.newMultiRolesAuthority(address(this), Authority(address(0)));
    vm.startPrank(systemAdmin);
    AuthController.setSubAuthority(address(router), address(vcv), sauth);
    vm.stopPrank();
  }

  function testVerifyCredential() public {
    SignedCredential memory sc = issueSC(agent);

    assertTrue(vcv.isValid(agent, sc.vc, sc.v, sc.r, sc.s));
  }

  function testVerifyCredentialFromWrongIssuer() public {
    uint256 qaPower = 10e10;

    AgentData memory _agent = AgentData(
      1e10, 100, 0, 0.5e18, 10e18, 10e18, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agent,
      block.number,
      block.number + 100,
      100,
      abi.encode(_agent)
    );

    bytes32 digest = vcv.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest);
    vm.expectRevert("VCVerifier: Not authorized");
    vcv.isValid(agent, vc, v, r, s);
  }

  function testBadIssuer() public {
    SignedCredential memory sc = issueSC(agent);

    sc.vc.issuer = makeAddr("FALSE_ISSUER");
    vm.expectRevert("VCVerifier: Not authorized");
    vcv.isValid(agent, sc.vc, sc.v, sc.r, sc.s);
  }

  function testFalseSubject() public {
    SignedCredential memory sc = issueSC(agent);

    sc.vc.subject = makeAddr("FALSE_SUBJECT");
    vm.expectRevert("VCVerifier: Not authorized");
    vcv.isValid(agent, sc.vc, sc.v, sc.r, sc.s);
  }

  // we don't use the issueGenericVC funcs because we dont use the AgentPolice as the VCVerifier
  function issueSC(address _agent) internal returns (SignedCredential memory) {
    uint256 qaPower = 10e18;

    AgentData memory agent = AgentData(
      1e10, 20e18, 0.5e18, 10e18, 10e18, 0, 10, qaPower, 5e18, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      _agent,
      block.number,
      block.number + 100,
      1000,
      abi.encode(agent)
    );

    bytes32 digest = vcv.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
    return SignedCredential(vc, v, r, s);
  }
}

