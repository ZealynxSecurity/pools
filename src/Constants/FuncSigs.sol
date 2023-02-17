// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/*//////////////////////////////////////////////////////////////
            FUNCTION SIGNATURES FOR ROLE AUTHORITY
//////////////////////////////////////////////////////////////*/

/**
 * @dev Function signatures are computed by:
 * 1. Add a new function signature, the naming convention follows:
 *    [CONTRACT]_[METHODNAME]_SELECTOR
 * 2. Set this value to empty bytes -> 0x0;
 * 3. Add a new test for this value in Constants.t.sol
 * 4. Let the test fail, extract the correct value
 * 5. Set the new function signature value to the correct value received in tests
 */

// ROUTER FUNCTION SIGNATURES
bytes4 constant ROUTER_PUSH_ROUTE_BYTES_SELECTOR = 0x334908b2;
bytes4 constant ROUTER_PUSH_ROUTE_STRING_SELECTOR = 0x19ac0743;
bytes4 constant ROUTER_PUSH_ROUTES_BYTES_SELECTOR = 0xef254abd;
bytes4 constant ROUTER_PUSH_ROUTES_STRING_SELECTOR = 0x7df3be51;

// AGENT FUNCTION SIGNATURES
bytes4 constant AGENT_ADD_MINERS_SELECTOR = 0x7225b865;
bytes4 constant AGENT_REMOVE_MINER_SELECTOR = 0x68deb85b;
bytes4 constant AGENT_CHANGE_MINER_WORKER_SELECTOR = 0x381d2960;
bytes4 constant AGENT_CHANGE_MINER_MULTIADDRS_SELECTOR = 0x18cb5023;
bytes4 constant AGENT_CHANGE_MINER_PEERID_SELECTOR = 0x8261ec81;

bytes4 constant AGENT_WITHDRAW_SELECTOR = 0x0cf20cc9;
bytes4 constant AGENT_WITHDRAW_WITH_CRED_SELECTOR = 0x71c2e442;
bytes4 constant AGENT_BORROW_SELECTOR = 0x9810f00f;
bytes4 constant AGENT_EXIT_SELECTOR = 0x8b9e0e42;
bytes4 constant AGENT_MAKE_PAYMENTS_SELECTOR = 0x7870020d;
bytes4 constant AGENT_STAKE_TO_MAKE_PAYMENTS_SELECTOR = 0x06c2447c;
bytes4 constant AGENT_PULL_FUNDS_SELECTOR = 0x17388a40;
bytes4 constant AGENT_PUSH_FUNDS_SELECTOR = 0xdb77e33a;
bytes4 constant AGENT_MINT_POWER_SELECTOR = 0x8bdba3a4;
bytes4 constant AGENT_BURN_POWER_SELECTOR = 0x5aa3a9b1;

// these are not being used right now because the agent police doesn't have roles besides its owner
bytes4 constant AGENT_POLICE_SET_WINDOW_PERIOD_SELECTOR = 0x0;
bytes4 constant AGENT_POLICE_SET_MAX_POOLS_PER_AGENT_SELECTOR = 0x0;
bytes4 constant AGENT_POLICE_LOCKOUT_SELECTOR = 0x0;

// AGENT FACTORY FUNCTION SIGNATURES
bytes4 constant AGENT_FACTORY_SET_VERIFIER_NAME_SELECTOR = 0xcc86c93a;

// AUTH FUNCTION SIGNATURES
bytes4 constant AUTH_SET_USER_ROLE_SELECTOR = 0x67aff484;
bytes4 constant AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR = 0x728b952b;

// POWER TOKEN FUNCTION SIGNATURES
bytes4 constant POWER_TOKEN_MINT_SELECTOR = 0xa0712d68;
bytes4 constant POWER_TOKEN_BURN_SELECTOR = 0x42966c68;

// ERC20 TOKEN FUNCTION SIGNATURES
bytes4 constant ERC20_TRANSFER_SELECTOR = 0xa9059cbb;
bytes4 constant ERC20_APPROVE_SELECTOR = 0x095ea7b3;
bytes4 constant ERC20_TRANSFER_FROM_SELECTOR = 0x23b872dd;
bytes4 constant ERC20_PERMIT_SELECTOR = 0xd505accf;

// MINER REGISTRY FUNCTION SIGNATURES
bytes4 constant MINER_REGISTRY_ADD_MINER_SELECTOR = 0xf3982e5e;
bytes4 constant MINER_REGISTRY_RM_MINER_SELECTOR = 0x10242590;
bytes4 constant MINER_REGISTRY_ADD_MINERS_SELECTOR = 0x7225b865;
bytes4 constant MINER_REGISTRY_RM_MINERS_SELECTOR = 0xaad4b6e8;

// ROUTER AWARE FUNCTION SIGNATURES
bytes4 constant ROUTER_AWARE_SET_ROUTER_SELECTOR = 0xc0d78655;

// POOL FINANCE FUNCTIONS
bytes4 constant POOL_BORROW_SELECTOR = 0x7433e485;
bytes4 constant POOL_EXIT_SELECTOR = 0xb78e52ea;

// POOL ADMIN FUNCTIONS
bytes4 constant POOL_FLUSH_SELECTOR = 0x6b9f96ea;
bytes4 constant POOL_SET_FEE_SELECTOR =  0x69fe0e2d;
bytes4 constant POOL_SHUT_DOWN_SELECTOR = 0x10b9e583;
bytes4 constant POOL_SET_MIN_LIQUIDITY_SELECTOR = 0x282567b4;
bytes4 constant POOL_SET_RAMP_SELECTOR = 0x3d9c3c17;
bytes4 constant POOL_SET_TEMPLATE_SELECTOR = 0x89c716d1;
bytes4 constant OFFRAMP_SET_CONVERSION_WINDOW_SELECTOR = 0x9ef89827;

// POOl FACTORY FUNCTIONS
bytes4 constant POOL_FACTORY_APPROVE_IMPLEMENTATION_SELECTOR = 0xf7fa1043;
bytes4 constant POOL_FACTORY_REVOKE_IMPLEMENTATION_SELECTOR = 0xe10ee285;
bytes4 constant POOL_FACTORY_APPROVE_TEMPLATE_SELECTOR = 0xa79cf51c;
bytes4 constant POOL_FACTORY_REVOKE_TEMPLATE_SELECTOR = 0xdb80bb9a;
bytes4 constant POOL_FACTORY_SET_TREASURY_FEE_SELECTOR = 0xce43303c;
bytes4 constant POOL_FACTORY_CREATE_POOL_SELECTOR = 0xdbffb761;
bytes4 constant POOL_FACTORY_SET_FEE_THRESHOLD_SELECTOR = 0xec1636b8;

// OVERLAPPING FUNCTION SIGNATURES
bytes4 constant SET_OPERATOR_ROLE_SELECTOR = 0x93512617;
bytes4 constant SET_OWNER_ROLE_SELECTOR = 0xe0afd38d;
bytes4 constant PAUSE_SELECTOR = 0x8456cb59;
bytes4 constant RESUME_SELECTOR = 0x046f7da2;

