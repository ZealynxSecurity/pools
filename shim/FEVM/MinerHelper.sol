// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {MinerAPI} from "filecoin-solidity/MinerAPI.sol";
import {MinerTypes} from "filecoin-solidity/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/types/CommonTypes.sol";
import {PrecompilesAPI} from "filecoin-solidity/PrecompilesAPI.sol";
import {SendAPI} from "filecoin-solidity/SendAPI.sol";
import {Misc} from "filecoin-solidity/utils/Misc.sol";

import "filecoin-solidity/utils/FilAddresses.sol";

library MinerHelper {

  using Misc for CommonTypes.ChainEpoch;

  error NegativeValueNotAllowed();

  /// @dev Only here to get the library to compile in test envs
  address constant ID_STORE_ADDR = address(0);
  /**
   * @notice Checks to see if a miner (`target`) is owned by `addr`
   * @param target The miner actor id you want to interact with
   * @param addr Expected owner address
   * @return isOwner - Returns true if the contract is the owner of the miner
   */
  function isOwner(uint64 target, address addr) internal returns (bool) {
    return keccak256(
      _getOwner(target)
    ) == keccak256(
      FilAddresses.fromActorID(
        PrecompilesAPI.resolveEthAddress(addr)
      ).data
    );
  }

  /**
   * @notice Returns the balance of the miner
   * @param target The miner actor id to get the balance of
   * @return balance - The FIL balance of the miner actor
   */
  function balance(uint64 target) internal returns (uint256 balance) {
    // here we do not check the success boolean because the available balance cannot overflow max uint256
    balance = toUint256(MinerAPI.getAvailableBalance(
      CommonTypes.FilActorId.wrap(target)
    ));
  }

  /**
   * @notice Sends FIL to the miner
   * @param target The miner actor id to send funds to
   * @param amount The amount of attofil to send
   */
  function transfer(uint64 target, uint256 amount) internal {
    SendAPI.send(CommonTypes.FilActorId.wrap(target), amount);
  }

  /**
   * @notice Ensures the miner actor does not have an active beneficiary that is not itself
   * @param target The miner actor id to send funds to
   * @return configuredForTakeover - Returns true if the miner is ready for takeover
   *
   * @dev beneficiaries: https://github.com/filecoin-project/builtin-actors/blob/6e09044f2514e1dfd92f41cc604812843eed2976/actors/miner/src/beneficiary.rs#L36
   * available to withdraw by beneficiary:
   * 0 when `expired`
   * 0 when the usedQuota >= Quota
   * otherwise beneficiary can withdraw, is not configuredForTakeover
   */
  function configuredForTakeover(uint64 target) internal returns (bool) {
    MinerTypes.GetBeneficiaryReturn memory ret =
      MinerAPI.getBeneficiary(CommonTypes.FilActorId.wrap(target));

    // if the beneficiary address is the miner's owner, then the agent will assume beneficiary
    if (keccak256(_getOwner(target)) == keccak256(ret.active.beneficiary.data)) {
      return true;
    }

    // if the beneficiary address is expired, then Agent will be ok to take ownership
    if (
      ret.active.term.expiration.getChainEpochSize() < block.timestamp
    ) return true;

    if (toUint256(ret.active.term.quota) <= toUint256(ret.active.term.used_quota)) return true;

    return false;
  }

  /**
   * @param target The miner actor id you want to interact with
   * @param addr New owner address
   * @notice Proposes or confirms a change of owner address.
   * @notice If invoked by the current owner, proposes a new owner address for confirmation. If the proposed address is the current owner address, revokes any existing proposal that proposed address.
   */
  function changeOwnerAddress(uint64 target, address addr) internal {
    MinerAPI.changeOwnerAddress(
      CommonTypes.FilActorId.wrap(target),
      FilAddresses.fromActorID(
        PrecompilesAPI.resolveEthAddress(addr)
      )
    );
  }


  /**
   * @notice Changes the worker address for a miner
   * @param target The miner actor id you want to interact with
   * @param workerAddr The new worker address
   * @param controllerAddrs The new controllers for the worker
   */
  function changeWorkerAddress(
    uint64 target,
    uint64 workerAddr,
    uint64[] calldata controllerAddrs
  ) external {
    // resolve the controllers
    CommonTypes.FilAddress[] memory controllers;
    for (uint256 i = 0; i < controllerAddrs.length; i++) {
      controllers[i] = FilAddresses.fromActorID(controllerAddrs[i]);
    }

    MinerAPI.changeWorkerAddress(
      CommonTypes.FilActorId.wrap(target),
      MinerTypes.ChangeWorkerAddressParams(
        FilAddresses.fromActorID(workerAddr),
        controllers
      )
    );
  }

  /**
   * @param target The miner actor id you want to interact with
   * @param amount the amount you want to withdraw
   *
   * @dev here we pack the amount into bytes and then pass it to the BigInt constructor
   */
  function withdrawBalance(uint64 target, uint256 amount)
    internal
    returns (uint256 amountWithdrawn)
  {
    MinerAPI.withdrawBalance(
      CommonTypes.FilActorId.wrap(target),
      CommonTypes.BigInt(abi.encodePacked(amount), false)
    );
  }

  function _getOwner(uint64 target) internal returns (bytes memory) {
    MinerAPI.getOwner(CommonTypes.FilActorId.wrap(target)).owner.data;
  }

  /// @dev None of the numbers we use according to Filecoin spec can overflow max uint256
  /// largest number can be 2 billion attofil
  function toUint256(CommonTypes.BigInt memory self) internal view returns (uint256 value) {
    if (self.neg) {
      revert NegativeValueNotAllowed();
    }

    return uint256(bytes32(self.val));
  }
}
