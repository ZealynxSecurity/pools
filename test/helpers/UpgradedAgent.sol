// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {Agent} from "src/Agent/Agent.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
error Unauthorized();
contract UpgradedAgent is Agent {
  using MinerHelper for uint64;

  uint64[] public miners;

  constructor(
    uint8 _version,
    uint256 _agentID,
    address _router,
    address _owner,
    address _operator,
    bytes memory _publicKey
  ) Agent(_version, _agentID, _router, _owner, _operator, _publicKey) {}

  function addMigratedMiners(uint64[] calldata migratedMiners) external onlyOwnerOperator {
    for (uint256 i = 0; i < migratedMiners.length; i++) {
      _addMinerNoRegistration(migratedMiners[i]);
    }
  }

  function _addMinerNoRegistration(uint64 miner) internal {
    // Confirm the miner is valid and can be added
    if (!miner.configuredForTakeover()) revert Unauthorized();

    // change the owner address
    miner.changeOwnerAddress(address(this));

    // add the miner to the agent's list of miners
    miners.push(miner);
  }
}
