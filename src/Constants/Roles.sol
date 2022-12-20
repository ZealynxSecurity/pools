// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

/*//////////////////////////////////////////////////////////////
                    ROLES FOR ROLE AUTHORITY
//////////////////////////////////////////////////////////////*/

// AGENT ROLES
uint8 constant ROLE_AGENT = 0;
uint8 constant ROLE_AGENT_OPERATOR = 1;
uint8 constant ROLE_AGENT_OWNER = 2;
uint8 constant ROLE_AGENT_FACTORY = 3;

// POOL ROLES
uint8 constant ROLE_POOL = 4;
uint8 constant ROLE_POOL_OPERATOR = 5;
uint8 constant ROLE_POOL_OWNER = 6;
uint8 constant ROLE_POOL_FACTORY = 7;

// ADMIN ROLES
uint8 constant ROLE_SETTER = 8;
uint8 constant ROLE_AGENT_FACTORY_ADMIN = 9;
uint8 constant ROLE_POOL_FACTORY_ADMIN = 10;
uint8 constant ROLE_ROUTER_ADMIN = 11;
uint8 constant ROLE_POWER_TOKEN_ADMIN = 12;
uint8 constant ROLE_MINER_REGISTRY_ADMIN = 13;
uint8 constant ROLE_SYSTEM_ADMIN = 14;

uint8 constant ROLE_VC_ISSUER = 15;
