// SPDX-License-Identifier: UNLICENSED
import {Agent} from "src/Agent/Agent.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
error Unauthorized();
contract UpgradedAgent is Agent {
  using MinerHelper for uint64;

  uint64[] public miners;

  constructor(
    address _router,
    uint256 _agentID,
    address _owner,
    address _operator
  ) Agent(_router, _agentID, _owner, _operator) {}

  function addMigratedMiners(uint64[] calldata miners) external onlyOwnerOperator {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMinerNoRegistration(miners[i]);
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
