// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// import "forge-std/Test.sol";
// import "src/Constants/FuncSigs.sol";
// import "src/Types/Structs/Filecoin.sol";
// import {VerifiableCredential, AgentData, SignedCredential} from "src/VCVerifier/VCVerifier.sol";
// import {AgentSigTester} from "./helpers/AgentTester.sol";
// import {PoolRegistrySigTester} from "./helpers/PoolRegistryTester.sol";

// contract AgentConstantsTest is Test {
//   SignedCredential sc;
//   AgentSigTester tester;

//   function setUp() public {
//     address issuer = makeAddr("ISSUER");

//     AgentData memory agent = AgentData(1e10, 20e18, 0.5e18, 10e18, 10e18, 0, 10, 10e18, 5e18, 0, 0);

//     VerifiableCredential memory vc = VerifiableCredential(
//       issuer,
//       makeAddr("SUBJECT"),
//       block.number,
//       block.number + 100,
//       1000,
//       abi.encode(agent)
//     );

//     sc = SignedCredential(vc, 0, 0x0, 0x0);

//     tester = new AgentSigTester();
//   }

//   function testAddMiners() public {
//     uint64[] memory miners = new uint64[](4);
//     miners[0] = 1000;
//     bytes4 funcSig = tester.addMiners(miners);
//     assertEq(funcSig, AGENT_ADD_MINERS_SELECTOR);
//   }

//   function testRemoveMiner() public {
//     bytes4 funcSig = tester.removeMiner(
//       makeAddr("MINER"),
//       1,
//       sc,
//       sc
//     );
//     assertEq(funcSig, AGENT_REMOVE_MINER_SELECTOR);
//   }

//   function testChangeMinerWorker() public {
//     uint64[] memory controlAddrs = new uint64[](1);
//     controlAddrs[0] = 1000;
//     bytes4 funcSig = tester.changeMinerWorker(
//       1000,
//       1000,
//       controlAddrs
//     );
//     assertEq(funcSig, AGENT_CHANGE_MINER_WORKER_SELECTOR);
//   }

//   function testSetOperator() public {
//     bytes4 funcSig = tester.setOperatorRole(
//       makeAddr("OPERATOR"),
//       true
//     );
//     assertEq(funcSig, SET_OPERATOR_ROLE_SELECTOR);
//   }

//   function testSetOwner() public {
//     bytes4 funcSig = tester.setOwnerRole(
//       makeAddr("OWNER"),
//       true
//     );
//     assertEq(funcSig, SET_OWNER_ROLE_SELECTOR);
//   }

//   function testMintPower() public {
//     bytes4 funcSig = tester.mintPower(
//       0,
//       sc
//     );
//     assertEq(funcSig, AGENT_MINT_POWER_SELECTOR);
//   }

//   function testBurnPower() public {
//     bytes4 funcSig = tester.burnPower(
//       0,
//       sc
//     );
//     assertEq(funcSig, AGENT_BURN_POWER_SELECTOR);
//   }

//   function testwithdrawWithCred() public {
//     bytes4 funcSig = tester.withdraw(
//       address(0),
//       0,
//       sc
//     );
//     assertEq(funcSig, AGENT_WITHDRAW_WITH_CRED_SELECTOR);
//   }

//   function testPullFundsFromMiners() public {
//     uint64[] memory miners = new uint64[](4);
//     miners[0] = 1000;
//     bytes4 funcSig = tester.pullFundsFromMiners(
//       miners,
//       new uint256[](0),
//       sc
//     );
//     assertEq(funcSig, AGENT_PULL_FUNDS_SELECTOR);
//   }

//   function testPushFundsToMiners() public {
//     uint64[] memory miners = new uint64[](4);
//     miners[0] = 1000;
//     bytes4 funcSig = tester.pushFundsToMiners(
//       miners,
//       new uint256[](0),
//       sc
//     );
//     assertEq(funcSig, AGENT_PUSH_FUNDS_SELECTOR);
//   }

//   function testBorrow() public {
//     bytes4 funcSig = tester.borrow(
//       0,
//       0,
//       sc,
//       0
//     );

//     assertEq(funcSig, AGENT_BORROW_SELECTOR);
//   }

//   function testExit() public {
//     bytes4 funcSig = tester.exit(
//       0,
//       0,
//       sc
//     );
//     assertEq(funcSig, AGENT_EXIT_SELECTOR);
//   }

//   function testMakePayments() public {
//     bytes4 funcSig = tester.makePayments(
//       new uint256[](0),
//       new uint256[](0),
//       sc
//     );
//     assertEq(funcSig, AGENT_MAKE_PAYMENTS_SELECTOR);
//   }

// }

// contract PoolRegistryConstantsTest is Test {
//   PoolRegistrySigTester tester;
//   function setUp() public {
//     tester = new PoolRegistrySigTester();
//   }

//   function testApproveImplementation() public {
//     bytes4 funcSig = tester.approveImplementation(address(0));
//     assertEq(funcSig, POOL_FACTORY_APPROVE_IMPLEMENTATION_SELECTOR);
//   }

//   function testRevokeImplementation() public {
//     bytes4 funcSig = tester.revokeImplementation(address(0));
//     assertEq(funcSig, POOL_FACTORY_REVOKE_IMPLEMENTATION_SELECTOR);
//   }

//   function testSetTreasuryFeeRate() public {
//     bytes4 funcSig = tester.setTreasuryFeeRate(0);
//     assertEq(funcSig, POOL_FACTORY_SET_TREASURY_FEE_SELECTOR);
//   }

//   function testCreatePool() public {
//     bytes4 funcSig = tester.createPool("", "", address(0), address(0));
//     assertEq(funcSig, POOL_FACTORY_CREATE_POOL_SELECTOR);
//   }

//   function testSetFeeThreshold() public {
//     bytes4 funcSig = tester.setFeeThreshold(0);
//     assertEq(funcSig, POOL_FACTORY_SET_FEE_THRESHOLD_SELECTOR);
//   }
// }

// contract ConstantsTest is Test {
//   VerifiableCredential vc;
//   MsgSigTester tester;

//   function setUp() public {
//     address issuer = makeAddr("ISSUER");

//     AgentData memory agent = AgentData(1e10, 20e18, 0, 0.5e18, 10e18, 10e18, 10, 10e18, 5e18, 0, 0);

//     vc = VerifiableCredential(
//       issuer,
//       makeAddr("SUBJECT"),
//       block.number,
//       block.number + 100,
//       1000,
//       abi.encode(agent)
//     );

//     tester = new MsgSigTester();
//   }


//   /**
//    * @dev Function signatures _must_ match the msg.sig value inside the function being called
//    * This test could be beefed up to call a fake interface with the same function signature
//    * and assert that the msg.sig value is the same as the function signature
//    *
//    * If msg.sig does not match the computed SELECTOR, the roles will not work.
//    */
//   function testFuncSigs() public {
//     assertEq(ROUTER_PUSH_ROUTE_BYTES_SELECTOR, bytes4(keccak256(bytes("pushRoute(bytes4,address)"))));
//     assertEq(ROUTER_PUSH_ROUTE_STRING_SELECTOR, bytes4(keccak256(bytes("pushRoute(string,address)"))));

//     // AGENT FACTORY FUNCTION SIGNATURES
//     assertEq(AGENT_FACTORY_SET_VERIFIER_NAME_SELECTOR, bytes4(keccak256(bytes("setVerifierName(string,string)"))));

//     // POWER TOKEN FUNCTION SIGNATURES
//     assertEq(POWER_TOKEN_MINT_SELECTOR, bytes4(keccak256(bytes("mint(uint256)"))));
//     assertEq(POWER_TOKEN_BURN_SELECTOR, bytes4(keccak256(bytes("burn(uint256)"))));

//     // AUTH FUNCTION SIGNATURES
//     assertEq(AUTH_SET_USER_ROLE_SELECTOR, bytes4(keccak256(bytes("setUserRole(address,uint8,bool)"))));
//     assertEq(AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, bytes4(keccak256(bytes("setTargetCustomAuthority(address,address)"))));

//     // ERC20 FUNCTION SIGNATURES
//     assertEq(ERC20_TRANSFER_SELECTOR, bytes4(keccak256(bytes("transfer(address,uint256)"))));
//     assertEq(ERC20_TRANSFER_FROM_SELECTOR, bytes4(keccak256(bytes("transferFrom(address,address,uint256)"))));
//     assertEq(ERC20_APPROVE_SELECTOR, bytes4(keccak256(bytes("approve(address,uint256)"))));
//     assertEq(ERC20_PERMIT_SELECTOR, bytes4(keccak256(bytes("permit(address,address,uint256,uint256,uint8,bytes32,bytes32)"))));

//     // MINER REGISTRY FUNCTION SIGNATURES
//     assertEq(MINER_REGISTRY_ADD_MINER_SELECTOR, bytes4(keccak256(bytes("addMiner(address)"))));
//     assertEq(MINER_REGISTRY_RM_MINER_SELECTOR, bytes4(keccak256(bytes("removeMiner(address)"))));

//     // ROUTER AWARE FUNCTION SIGNATURES
//     assertEq(ROUTER_AWARE_SET_ROUTER_SELECTOR, bytes4(keccak256(bytes("setRouter(address)"))));

//     // POOL ADMIN FUNCTION SIGNATURES
//     assertEq(POOL_FLUSH_SELECTOR, bytes4(keccak256(bytes("flush()"))));
//     assertEq(POOL_SET_FEE_SELECTOR, bytes4(keccak256(bytes("setFee(uint256)"))));
//     assertEq(OFFRAMP_SET_CONVERSION_WINDOW_SELECTOR, bytes4(keccak256(bytes("setConversionWindow(uint256)"))));
//     assertEq(POOL_SHUT_DOWN_SELECTOR, bytes4(keccak256(bytes("shutDown()"))));
//     assertEq(POOL_SET_MIN_LIQUIDITY_SELECTOR, bytes4(keccak256(bytes("setMinimumLiquidity(uint256)"))));
//     assertEq(POOL_SET_RAMP_SELECTOR, bytes4(keccak256(bytes("setRamp(address)"))));
//     assertEq(POOL_SET_IMPLEMENTATION_SELECTOR, bytes4(keccak256(bytes("setImplementation(address)"))));

//     assertEq(PAUSE_SELECTOR, bytes4(keccak256(bytes("pause()"))));
//     assertEq(RESUME_SELECTOR, bytes4(keccak256(bytes("resume()"))));
//   }

//   // array types are harder to encode in the function signature
//   // so we make a test contract to return the msg.sig within the call to check against our static values
//   function testAddRmMinersFuncSigs() public {
//     bytes4 addMinersSig = tester.addMiners(new address[](0));
//     bytes4 rmMinersSig = tester.removeMiners(new address[](0));

//     assertEq(addMinersSig, MINER_REGISTRY_ADD_MINERS_SELECTOR);
//     assertEq(rmMinersSig, MINER_REGISTRY_RM_MINERS_SELECTOR);
//   }

//   function testPushRoutes() public {
//     bytes4 pushRoutesSig = tester.pushRoutes(new string[](0), new address[](0));
//     bytes4 pushRoutesSig2 = tester.pushRoutes(new bytes4[](0), new address[](0));

//     assertEq(pushRoutesSig, ROUTER_PUSH_ROUTES_STRING_SELECTOR);
//     assertEq(pushRoutesSig2, ROUTER_PUSH_ROUTES_BYTES_SELECTOR);
//   }

//   function testPoolBorrowFuncSig() public {
//     bytes4 poolBorrowSig = tester.borrow(0, vc, 0);
//     assertEq(poolBorrowSig, POOL_BORROW_SELECTOR);
//   }

//   function testExitPoolFuncSig() public {
//     bytes4 expitPoolSig = tester.exitPool(0, vc);
//     assertEq(expitPoolSig, POOL_EXIT_SELECTOR);
//   }
// }


// contract MsgSigTester {
//   function addMiners(address[] calldata) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   function removeMiners(address[] calldata) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   function pushRoutes(string[] calldata, address[] calldata) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   function pushRoutes(bytes4[] calldata, address[] calldata) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   // Pool finance functions
//   function borrow(
//     uint256,
//     VerifiableCredential memory,
//     uint256
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   function exitPool(
//     uint256,
//     VerifiableCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }

//   function makePayment(
//     address,
//     VerifiableCredential memory
//   ) external pure returns (bytes4) {
//     return msg.sig;
//   }
// }
