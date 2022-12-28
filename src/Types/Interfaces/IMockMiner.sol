// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Types/Structs/Filecoin.sol";

// note this interface is like halfway to the filecoin.sol library
// the methods take the miner address as the first param like the library does
// but we call these methods off a MockMiner contract so it can hold state for testing
interface IMockMiner {
	function get_owner(address miner) external view returns (address);
  function next_owner(address miner) external view returns (address); // ?
  function get_beneficiary(address miner) external view returns (address);

  function change_worker_address(
    address miner,
    ChangeWorkerAddressParams memory params
  ) external;

  function change_peer_id(
    address miner,
    ChangePeerIDParams memory params
  ) external;

  function change_multiaddresses(
    address miner,
    ChangeMultiaddrsParams memory params
  ) external;

  // If changeOwnerAddress is called by the current owner, its a proposal to change owner to newOwner
  // If changeOwnerAddress is called by the proposed next owner, its a confirmation accepting the change of ownership
  function change_owner_address(address miner, address newOwner) external;
  // if attempt to withdrawBalance with an amount greater than balance avail, this will throw an insufficient funds err
  function withdrawBalance(uint256 amount) external returns (uint256);
  // used for pledging collateral
  function applyRewards(uint256 reward, uint256 penalty) external;
	// just used for simulating rewards
	function lockBalance(
    uint256 _lockStart,
    uint256 _unlockDuration,
    uint256 _unlockAmount
  ) external;
}
