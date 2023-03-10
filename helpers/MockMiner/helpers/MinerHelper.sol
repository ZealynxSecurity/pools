// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IMockMiner} from "test/helpers/IMockMiner.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import "src/Types/Structs/Filecoin.sol";

library MinerHelper {
  // the ID store gets deployed at the same address every time in a test env
  address constant ID_STORE_ADDR = address(0x74C8a71d2876D3153D1CCC64da2818A5cd07dDf5);

  /// @param target The miner actor id you want to interact with
  /// @param addr Expected owner address
  /// @return Returns true if the contract is the owner of the miner
  function isOwner(uint64 target, address addr) internal returns (bool) {
    return IMockMiner(MockIDAddrStore(ID_STORE_ADDR).ids(target)).owner() == addr;
  }

  function proposedOwner(uint64 target) internal returns (address) {
    return IMockMiner(MockIDAddrStore(ID_STORE_ADDR).ids(target)).proposed();
  }

  function balance(uint64 target) internal view returns (uint256) {
    return address(payable(MockIDAddrStore(ID_STORE_ADDR).ids(target))).balance;
  }

  function transfer(uint64 target, uint256 amount) internal {
    (bool success, ) = MockIDAddrStore(ID_STORE_ADDR).ids(target).call{value: amount}("");
    require(success, "Failed to send funds to miner");
  }

  function configuredForTakeover(uint64 target) internal view returns (bool) {
    require(getBeneficiary(target).active.beneficiary == 0, "cannot takeover miner with active beneficiary");

    return true;
  }

  /// @param target The miner actor id you want to interact with
  /// @param addr New owner address
  /// @notice Proposes or confirms a change of owner address.
  /// @notice If invoked by the current owner, proposes a new owner address for confirmation. If the proposed address is the current owner address, revokes any existing proposal that proposed address.
  function changeOwnerAddress(uint64 target, address addr) internal {
    IMockMiner(MockIDAddrStore(ID_STORE_ADDR).ids(target)).changeOwnerAddress(addr);
  }

  /// @param target The miner actor id you want to interact with
  /// @notice This method is for use by other actors (such as those acting as beneficiaries), and to abstract the state representation for clients.
  /// @notice Retrieves the currently active and proposed beneficiary information.
  function getBeneficiary(uint64 target) internal view returns (GetBeneficiaryReturn memory) {
    return IMockMiner(MockIDAddrStore(ID_STORE_ADDR).ids(target)).getBeneficiary();
  }

  function changeWorkerAddress(
    uint64 target,
    uint64 worker,
    uint64[] memory controlAddrs
  ) internal {
  }

  /// @param target The miner actor id you want to interact with
  /// @param amount the amount you want to withdraw
  function withdrawBalance(uint64 target, uint256 amount) internal returns (uint256 amountWithdrawn) {
    amountWithdrawn = IMockMiner(MockIDAddrStore(ID_STORE_ADDR).ids(target)).withdrawBalance(amount);
  }
}
