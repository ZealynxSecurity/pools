// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

library Routes {
  bytes4 public constant AGENT_FACTORY = bytes4(keccak256(bytes("ROUTER_AGENT_FACTORY")));
  bytes4 public constant POOL_FACTORY = bytes4(keccak256(bytes("ROUTER_POOL_FACTORY")));
  bytes4 public constant VC_VERIFIER = bytes4(keccak256(bytes("ROUTER_VC_VERIFIER")));
  bytes4 public constant STATS = bytes4(keccak256(bytes("ROUTER_STATS")));
  bytes4 public constant MINER_REGISTRY = bytes4(keccak256(bytes("ROUTER_MINER_REGISTRY")));
  bytes4 public constant AUTHORITY = bytes4(keccak256(bytes("ROUTER_AUTHORIY")));
  bytes4 public constant POWER_TOKEN = bytes4(keccak256(bytes("ROUTER_POWER_TOKEN")));
}
