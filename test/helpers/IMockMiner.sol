// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/Types/Structs/Filecoin.sol";

// note this interface is like halfway to the filecoin.sol library
// the methods take the miner address as the first param like the library does
// but we call these methods off a MockMiner contract so it can hold state for testing
interface IMockMiner {
  function owner() external returns (address);
  function proposed() external returns (address);
  function id() external returns (uint64);

  function changeOwnerAddress(address newOwner) external;
  function getBeneficiary() external view returns (GetBeneficiaryReturn memory);
  function changeWorkerAddress(uint64, uint64[] memory) external;
  function withdrawBalance(uint256 amount) external returns (uint256 amountWithdrawn);
}
