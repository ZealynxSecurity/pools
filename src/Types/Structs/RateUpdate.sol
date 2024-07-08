// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

struct RateUpdate {
    uint256 totalAccountsAtUpdate;
    uint256 totalAccountsClosed;
    uint256 newRate;
    bool inProcess;
}
