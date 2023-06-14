// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "src/VCVerifier/VCVerifier.sol";
import {errorSelector} from "./helpers/Utils.sol";
import "./BaseTest.sol";

contract VCVerifierMock is VCVerifier {
  constructor(
    address _router,
    string memory verifiedName,
    string memory verifiedVersion
  ) VCVerifier(verifiedName, verifiedVersion, _router) {
  }
}

contract VCVerifierTest is BaseTest {
  VCVerifierMock public vcv;
  uint256 public agentID = 1;

  function setUp() public {
    vcv = new VCVerifierMock(address(router), "glif.io", "1");
  }

  function testVerifyCredential() public {
    SignedCredential memory sc = _issueSC(agentID);

    try vcv.validateCred(agentID, 0x0, sc) {
      assertTrue(true);
    } catch {
      assertTrue(false, "Should be a valid cred");
    }
  }

  function testVerifyCredentialFromWrongIssuer() public {
    uint256 agentValue = 10e18;
    uint256 collateralValue = agentValue * 60 / 100;

    AgentData memory agent = AgentData(
      agentValue, collateralValue, 0, 500, GCRED, 10e18, 5e18, 0, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      agentID,
      block.number,
      block.number + 100,
      1000,
      // no specific action in this cred
      0x0,
      // no specific target in this cred
      0,
      abi.encode(agent)
    );

    bytes32 digest = vcv.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(2, digest);
    SignedCredential memory sc = SignedCredential(vc, v, r, s);
    try vcv.validateCred(agentID, 0x0, sc) {
      assertTrue(false, "Credential should be invalid - wrong issuer");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
    }
  }

  function testBadIssuer() public {
    SignedCredential memory sc = _issueSC(agentID);

    sc.vc.issuer = makeAddr("FALSE_ISSUER");

    try vcv.validateCred(agentID, 0x0, sc) {
      assertTrue(false, "Credential should be invalid - bad issuer");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
    }
  }

  function testSubjectZero() public {
    SignedCredential memory sc = _issueSC(agentID);

    sc.vc.subject = 0;

    try vcv.validateCred(agentID, 0x0, sc) {
      assertTrue(false, "Credential should be invalid - bad subject");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
    }
  }

  function testFalseSubject() public {
    SignedCredential memory sc = _issueSC(agentID);

    sc.vc.subject = 2;
    try vcv.validateCred(agentID, 0x0, sc) {
      assertTrue(false, "Credential should be invalid - false subject");
    } catch (bytes memory e) {
      assertEq(errorSelector(e), VCVerifier.InvalidCredential.selector);
    }
  }

  // we don't use the generic funcs because we dont use the AgentPolice as the VCVerifier
  function _issueSC(uint256 _agent) internal returns (SignedCredential memory) {
    uint256 agentValue = 10e18;
    uint256 collateralValue = agentValue * 60 / 100;

    AgentData memory agent = AgentData(
      agentValue, collateralValue, 0, 500, 80, 10e18, 5e18, 0, 0, 0
    );

    VerifiableCredential memory vc = VerifiableCredential(
      vcIssuer,
      _agent,
      block.number,
      block.number + 100,
      1000,
      // no specific action in this cred
      0x0,
      // no specific target in this cred
      0,
      abi.encode(agent)
    );

    bytes32 digest = vcv.digest(vc);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
    return SignedCredential(vc, v, r, s);
  }


}

