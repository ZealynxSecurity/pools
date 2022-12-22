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
bytes4 constant AGENT_ADD_MINER_SELECTOR = 0xf3982e5e;
bytes4 constant AGENT_REMOVE_MINER_ADDR_SELECTOR = 0x10242590;
bytes4 constant AGENT_REMOVE_MINER_INDEX_SELECTOR = 0x88e8e6fa;
bytes4 constant AGENT_REVOKE_OWNERSHIP_SELECTOR = 0xbd860e9a;
bytes4 constant AGENT_WITHDRAW_SELECTOR = 0x756af45f;
bytes4 constant AGENT_BORROW_SELECTOR = 0x425664f2;
bytes4 constant AGENT_REPAY_SELECTOR = 0xd8aed145;
bytes4 constant AGENT_MINT_POWER_SELECTOR = 0x62cf290b;
bytes4 constant AGENT_BURN_POWER_SELECTOR = 0x7fbb319b;
bytes4 constant AGENT_EXIT_SELECTOR = 0x91c9f10a;

// AGENT FACTORY FUNCTION SIGNATURES
bytes4 constant AGENT_FACTORY_SET_VERIFIER_NAME_SELECTOR = 0xcc86c93a;

// AUTH FUNCTION SIGNATURES
bytes4 constant AUTH_SET_USER_ROLE_SELECTOR = 0x67aff484;
bytes4 constant AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR = 0x728b952b;

// POWER TOKEN FUNCTION SIGNATURES
bytes4 constant POWER_TOKEN_MINT_SELECTOR = 0xa0712d68;
bytes4 constant POWER_TOKEN_BURN_SELECTOR = 0x42966c68;
bytes4 constant POWER_TOKEN_PAUSE_SELECTOR = 0x0;
bytes4 constant POWER_TOKEN_RESUME_SELECTOR = 0x0;

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
bytes4 constant POOL_BORROW_SELECTOR = 0x3a085280;
bytes4 constant POOL_EXIT_SELECTOR = 0x91c9f10a;

// POOL ADMIN FUNCTIONS
bytes4 constant POOL_FLUSH_SELECTOR = 0x6b9f96ea;
bytes4 constant POOL_ENABLE_OPERATOR_SELECTOR = 0x0;
bytes4 constant POOL_DISABLE_OPERATOR_SELECTOR = 0x0;
bytes4 constant POOL_SET_RATE_MODULE_SELECTOR = 0x0;

// OVERLAPPING FUNCTION SIGNATURES
bytes4 constant MAKE_PAYMENT_SELECTOR = 0x20a68725;
bytes4 constant ENABLE_OPERATOR_SELECTOR = 0xdd307b99;
bytes4 constant DISABLE_OPERATOR_SELECTOR = 0xf56408ed;
bytes4 constant ENABLE_OWNER_SELECTOR = 0xad31c7f2;
bytes4 constant DISABLE_OWNER_SELECTOR = 0xd02c72c8;

