// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

bytes4 constant ROUTE_AGENT_FACTORY = bytes4(keccak256(bytes("ROUTER_AGENT_FACTORY")));
bytes4 constant ROUTE_POOL_REGISTRY = bytes4(keccak256(bytes("ROUTER_POOL_REGISTRY")));
bytes4 constant ROUTE_MINER_REGISTRY = bytes4(keccak256(bytes("ROUTER_MINER_REGISTRY")));
bytes4 constant ROUTE_WFIL_TOKEN = bytes4(keccak256(bytes("ROUTER_WFIL_TOKEN")));
bytes4 constant ROUTE_SYSTEM_ADMIN = bytes4(keccak256(bytes("ROUTER_ADMIN")));
bytes4 constant ROUTE_VC_ISSUER = bytes4(keccak256(bytes("ROUTER_VC_ISSUER")));
bytes4 constant ROUTE_TREASURY = bytes4(keccak256(bytes("ROUTER_TREASURY")));
bytes4 constant ROUTE_AGENT_POLICE = bytes4(keccak256(bytes("ROUTER_AGENT_POLICE")));
bytes4 constant ROUTE_CRED_PARSER = bytes4(keccak256(bytes("ROUTER_CRED_PARSER")));
bytes4 constant ROUTE_AGENT_DEPLOYER = bytes4(keccak256(bytes("ROUTER_AGENT_DEPLOYER")));
