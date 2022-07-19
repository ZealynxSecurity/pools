// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

interface IMiner {
	function currentOwner() external view returns (address);
  function nextOwner() external view returns (address);
  // If changeOwnerAddress is called by the current owner, its a proposal to change owner to newOwner
  // If changeOwnerAddress is called by the proposed next owner, its a confirmation accepting the change of ownership
  function changeOwnerAddress(address newOwner) external;
  // if attempt to withdrawBalance with an amount greater than balance avail, this will throw an insufficient funds err
  function withdrawBalance(uint256 amount) external returns (uint256);
  // used for pledging collateral
  function applyRewards(uint256 reward, uint256 penalty) external;
	// just used for simulating rewards
	function lockBalance(uint256 _lockStart, uint256 _unlockDuration,  uint256 _unlockAmount) external;
}

/**
		Miner actor functions

		builtin.MethodConstructor: a.Constructor,
		2:                         a.ControlAddresses,
		3:                         a.ChangeWorkerAddress,
		4:                         a.ChangePeerID,
		5:                         a.SubmitWindowedPoSt,
		6:                         a.PreCommitSector,
		7:                         a.ProveCommitSector,
		8:                         a.ExtendSectorExpiration,
		9:                         a.TerminateSectors,
		10:                        a.DeclareFaults,
		11:                        a.DeclareFaultsRecovered,
		12:                        a.OnDeferredCronEvent,
		13:                        a.CheckSectorProven,
		14:                        a.ApplyRewards,
		15:                        a.ReportConsensusFault,
		16:                        a.WithdrawBalance,
		17:                        a.ConfirmSectorProofsValid,
		18:                        a.ChangeMultiaddrs,
		19:                        a.CompactPartitions,
		20:                        a.CompactSectorNumbers,
		21:                        a.ConfirmUpdateWorkerKey,
		22:                        a.RepayDebt,
		23:                        a.ChangeOwnerAddress,
		24:                        a.DisputeWindowedPoSt,
		25:                        a.PreCommitSectorBatch,
		26:                        a.ProveCommitAggregate,
		27:                        a.ProveReplicaUpdates,
 */
