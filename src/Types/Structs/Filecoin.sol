// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

struct ChangeWorkerAddressParams {
  bytes new_worker;
  bytes[] new_control_addresses;
}

struct ChangeMultiaddrsParams {
  bytes[] new_multi_addrs;
}

struct ChangePeerIDParams {
  bytes new_id;
}
