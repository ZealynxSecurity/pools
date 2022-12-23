// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Constants/FuncSigs.sol";
import {VerifiableCredential, MinerData} from "src/VCVerifier/VCVerifier.sol";

contract ConstantsTest is Test {
  VerifiableCredential vc;
  MsgSigTester tester;

  function setUp() public {
    address issuer = makeAddr("ISSUER");

    MinerData memory miner = MinerData(1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 0, 10, 10e18, 5e18, 0, 0);

    vc = VerifiableCredential(
      issuer,
      makeAddr("SUBJECT"),
      block.number,
      block.number + 100,
      miner
    );

    tester = new MsgSigTester();
  }

  /**
   * @dev Function signatures _must_ match the msg.sig value inside the function being called
   * This test could be beefed up to call a fake interface with the same function signature
   * and assert that the msg.sig value is the same as the function signature
   *
   * If msg.sig does not match the computed SELECTOR, the roles will not work.
   */
  function testFuncSigs() public {
    assertEq(ROUTER_PUSH_ROUTE_BYTES_SELECTOR, bytes4(keccak256(bytes("pushRoute(bytes4,address)"))));
    assertEq(ROUTER_PUSH_ROUTE_STRING_SELECTOR, bytes4(keccak256(bytes("pushRoute(string,address)"))));

    // AGENT FUNCTION SIGNATURES
    assertEq(AGENT_ADD_MINER_SELECTOR, bytes4(keccak256(bytes("addMiner(address)"))));
    assertEq(AGENT_REMOVE_MINER_ADDR_SELECTOR, bytes4(keccak256(bytes("removeMiner(address)"))));
    assertEq(AGENT_REMOVE_MINER_INDEX_SELECTOR, bytes4(keccak256(bytes("removeMiner(uint256)"))));
    assertEq(AGENT_REVOKE_OWNERSHIP_SELECTOR, bytes4(keccak256(bytes("revokeOwnership(address,address)"))));
    assertEq(ENABLE_OPERATOR_SELECTOR, bytes4(keccak256(bytes("enableOperator(address)"))));
    assertEq(DISABLE_OPERATOR_SELECTOR, bytes4(keccak256(bytes("disableOperator(address)"))));
    assertEq(ENABLE_OWNER_SELECTOR, bytes4(keccak256(bytes("enableOwner(address)"))));
    assertEq(DISABLE_OWNER_SELECTOR, bytes4(keccak256(bytes("disableOwner(address)"))));
    assertEq(AGENT_WITHDRAW_SELECTOR, bytes4(keccak256(bytes("withdrawBalance(address)"))));
    assertEq(AGENT_REPAY_SELECTOR, bytes4(keccak256(bytes("repay(uint256,uint256)"))));

    // AGENT FACTORY FUNCTION SIGNATURES
    assertEq(AGENT_FACTORY_SET_VERIFIER_NAME_SELECTOR, bytes4(keccak256(bytes("setVerifierName(string,string)"))));

    // POWER TOKEN FUNCTION SIGNATURES
    assertEq(POWER_TOKEN_MINT_SELECTOR, bytes4(keccak256(bytes("mint(uint256)"))));
    assertEq(POWER_TOKEN_BURN_SELECTOR, bytes4(keccak256(bytes("burn(uint256)"))));

    // AUTH FUNCTION SIGNATURES
    assertEq(AUTH_SET_USER_ROLE_SELECTOR, bytes4(keccak256(bytes("setUserRole(address,uint8,bool)"))));
    assertEq(AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, bytes4(keccak256(bytes("setTargetCustomAuthority(address,address)"))));

    // POWER TOKEN FUNCTION SIGNATURES
    assertEq(POWER_TOKEN_MINT_SELECTOR, bytes4(keccak256(bytes("mint(uint256)"))));
    assertEq(POWER_TOKEN_BURN_SELECTOR, bytes4(keccak256(bytes("burn(uint256)"))));

    // ERC20 FUNCTION SIGNATURES
    assertEq(ERC20_TRANSFER_SELECTOR, bytes4(keccak256(bytes("transfer(address,uint256)"))));
    assertEq(ERC20_TRANSFER_FROM_SELECTOR, bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))));
    assertEq(ERC20_APPROVE_SELECTOR, bytes4(keccak256(bytes("approve(address,uint256)"))));
    assertEq(ERC20_PERMIT_SELECTOR, bytes4(keccak256(bytes("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))));

    // MINER REGISTRY FUNCTION SIGNATURES
    assertEq(MINER_REGISTRY_ADD_MINER_SELECTOR, bytes4(keccak256(bytes("addMiner(address)"))));
    assertEq(MINER_REGISTRY_RM_MINER_SELECTOR, bytes4(keccak256(bytes("removeMiner(address)"))));

    // ROUTER AWARE FUNCTION SIGNATURES
    assertEq(ROUTER_AWARE_SET_ROUTER_SELECTOR, bytes4(keccak256(bytes("setRouter(address)"))));

    // POOL ADMIN FUNCTION SIGNATURES
    assertEq(POOL_FLUSH_SELECTOR, bytes4(keccak256(bytes("flush()"))));

    assertEq(PAUSE_SELECTOR, bytes4(keccak256(bytes("pause()"))));
    assertEq(RESUME_SELECTOR, bytes4(keccak256(bytes("resume()"))));
  }

  // array types are harder to encode in the function signature
  // so we make a test contract to return the msg.sig within the call to check against our static values
  function testAddRmMinersFuncSigs() public {
    bytes4 addMinersSig = tester.addMiners(new address[](0));
    bytes4 rmMinersSig = tester.removeMiners(new address[](0));

    assertEq(addMinersSig, MINER_REGISTRY_ADD_MINERS_SELECTOR);
    assertEq(rmMinersSig, MINER_REGISTRY_RM_MINERS_SELECTOR);
  }

  function testMintBurnPower() public {
    bytes4 mintSig = tester.mintPower(0, vc, 0, bytes32(0), bytes32(0));
    bytes4 burnSig = tester.burnPower(0, vc, 0, bytes32(0), bytes32(0));

    assertEq(mintSig, AGENT_MINT_POWER_SELECTOR);
    assertEq(burnSig, AGENT_BURN_POWER_SELECTOR);
  }

  function testPushRoutes() public {
    bytes4 pushRoutesSig = tester.pushRoutes(new string[](0), new address[](0));
    bytes4 pushRoutesSig2 = tester.pushRoutes(new bytes4[](0), new address[](0));

    assertEq(pushRoutesSig, ROUTER_PUSH_ROUTES_STRING_SELECTOR);
    assertEq(pushRoutesSig2, ROUTER_PUSH_ROUTES_BYTES_SELECTOR);
  }

  function testPoolBorrowFuncSig() public {
    bytes4 poolBorrowSig = tester.borrow(0, vc, 0);
    assertEq(poolBorrowSig, POOL_BORROW_SELECTOR);
  }

  function testExitPoolFuncSig() public {
    bytes4 expitPoolSig = tester.exit(0, vc, 0, 0x0, 0x0);
    assertEq(expitPoolSig, POOL_EXIT_SELECTOR);
  }

  function testAgentBorrowFuncSig() public {
    bytes4 agentBorrowSig = tester.borrow(0, 0, vc, 0, 0, 0x0, 0x0);
    assertEq(agentBorrowSig, AGENT_BORROW_SELECTOR);
  }

  function testAgentExitFuncSig() public {
    bytes4 agentExitSig = tester.exit(0, vc, 0, 0x0, 0x0);
    assertEq(agentExitSig, AGENT_EXIT_SELECTOR);
  }

  // NOTE: this func sig is the same for pools and for agents
  function testMakePayment() public {
    bytes4 makePmtFuncSig = tester.makePayment(address(0), vc);
    assertEq(makePmtFuncSig, MAKE_PAYMENT_SELECTOR);
  }
}

contract MsgSigTester {
  function addMiners(address[] calldata) external pure returns (bytes4) {
    return msg.sig;
  }

  function removeMiners(address[] calldata) external pure returns (bytes4) {
    return msg.sig;
  }

  function mintPower(uint256, VerifiableCredential memory, uint8, bytes32, bytes32) public pure returns (bytes4) {
    return msg.sig;
  }

  function burnPower(uint256, VerifiableCredential memory, uint8, bytes32, bytes32) public pure returns (bytes4) {
    return msg.sig;
  }

  function pushRoutes(string[] calldata, address[] calldata) external pure returns (bytes4) {
    return msg.sig;
  }

  function pushRoutes(bytes4[] calldata, address[] calldata) external pure returns (bytes4) {
    return msg.sig;
  }

  // Pool finance functions
  function borrow(
    uint256,
    VerifiableCredential memory,
    uint256
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  function exitPool(
    uint256,
    VerifiableCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  function makePayment(
    address,
    VerifiableCredential memory
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  // Pool Admin Funcs
  function flush() external pure returns (bytes4) {
    return msg.sig;
  }

  // Agent finance funcs
  function borrow(
    uint256,
    uint256,
    VerifiableCredential memory,
    uint256,
    uint8,
    bytes32,
    bytes32
  ) external pure returns (bytes4) {
    return msg.sig;
  }

  function exit(
    uint256,
    VerifiableCredential memory,
    uint8,
    bytes32,
    bytes32
  ) external pure returns (bytes4) {
    return msg.sig;
  }
}
