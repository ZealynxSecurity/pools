// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

bytes4 constant ROUTE_AGENT_FACTORY = bytes4(keccak256(bytes("ROUTER_AGENT_FACTORY")));
bytes4 constant ROUTE_POOL_FACTORY = bytes4(keccak256(bytes("ROUTER_POOL_FACTORY")));
bytes4 constant ROUTE_STATS = bytes4(keccak256(bytes("ROUTER_STATS")));
bytes4 constant ROUTE_MINER_REGISTRY = bytes4(keccak256(bytes("ROUTER_MINER_REGISTRY")));
bytes4 constant ROUTE_CORE_AUTHORITY = bytes4(keccak256(bytes("ROUTER_AUTHORIY")));
bytes4 constant ROUTE_POWER_TOKEN = bytes4(keccak256(bytes("ROUTER_POWER_TOKEN")));
bytes4 constant ROUTE_WFIL_TOKEN = bytes4(keccak256(bytes("ROUTER_WFIL_TOKEN")));
bytes4 constant ROUTE_ROUTER_ADMIN = bytes4(keccak256(bytes("ROUTER_ADMIN")));
bytes4 constant ROUTE_AGENT_FACTORY_ADMIN = bytes4(keccak256(bytes("ROUTER_AGENT_FACTORY_ADMIN")));
bytes4 constant ROUTE_POWER_TOKEN_ADMIN = bytes4(keccak256(bytes("ROUTER_POWER_TOKEN_ADMIN")));
bytes4 constant ROUTE_MINER_REGISTRY_ADMIN = bytes4(keccak256(bytes("ROUTER_MINER_REGISTRY_ADMIN")));
bytes4 constant ROUTE_POOL_FACTORY_ADMIN = bytes4(keccak256(bytes("ROUTER_POOL_FACTORY_ADMIN")));
bytes4 constant ROUTE_CORE_AUTH_ADMIN = bytes4(keccak256(bytes("ROUTER_CORE_AUTHORIY_ADMIN")));
bytes4 constant ROUTE_VC_ISSUER = bytes4(keccak256(bytes("ROUTER_VC_ISSUER")));
bytes4 constant ROUTE_TREASURY = bytes4(keccak256(bytes("ROUTER_TREASURY")));
bytes4 constant ROUTE_TREASURY_ADMIN = bytes4(keccak256(bytes("ROUTER_TREASURY_ADMIN")));
