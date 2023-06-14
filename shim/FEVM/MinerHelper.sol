// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MinerAPI} from "filecoin-solidity/MinerAPI.sol";
import {MinerTypes} from "filecoin-solidity/types/MinerTypes.sol";
import {CommonTypes} from "filecoin-solidity/types/CommonTypes.sol";
import {PrecompilesAPI} from "filecoin-solidity/PrecompilesAPI.sol";
import {SendAPI} from "filecoin-solidity/SendAPI.sol";
import {Misc} from "filecoin-solidity/utils/Misc.sol";
import {BigInts} from "filecoin-solidity/utils/BigInts.sol";

import "filecoin-solidity/utils/FilAddresses.sol";

library MinerHelper {

  using Misc for CommonTypes.ChainEpoch;
  using BigInts for CommonTypes.BigInt;

  /// @dev Only here to get the library to compile in test envs
  address constant ID_STORE_ADDR = address(0);
  /**
   * @notice Checks to see if a miner (`target`) is owned by `addr`
   * @param target The miner actor id you want to interact with
   * @param addr Expected owner address
   * @return isOwner - Returns true if the contract is the owner of the miner
   */
  function isOwner(uint64 target, address addr) internal returns (bool) {
    return _getOwner(_getMinerId(target)) == PrecompilesAPI.resolveEthAddress(addr);
  }

  /**
   * @notice Returns the balance of the miner
   * @param target The miner actor id to get the balance of
   * @return balance - The FIL balance of the miner actor
   */
  function balance(uint64 target) internal returns (uint256) {
    // here we do not check the success boolean because the available balance cannot overflow max uint256
    return _toUint256(MinerAPI.getAvailableBalance(_getMinerId(target)));
  }

  /**
   * @notice Sends FIL to the miner
   * @param target The miner actor id to send funds to
   * @param amount The amount of attofil to send
   */
  function transfer(uint64 target, uint256 amount) internal {
    SendAPI.send(_getMinerId(target), amount);
  }

  /**
   * @notice Ensures the miner actor does not have an active beneficiary that is not itself
   * @param target The miner actor id to send funds to
   * @return configuredForTakeover - Returns true if the miner is ready for takeover
   *
   * @dev beneficiaries: https://github.com/filecoin-project/builtin-actors/blob/6e09044f2514e1dfd92f41cc604812843eed2976/actors/miner/src/beneficiary.rs#L36
   * available to withdraw by beneficiary:
   * 0 when `expired`
   * otherwise beneficiary can withdraw, is not configuredForTakeover
   *
   * Note we do not check any quota here for a few reasons:
   * 1. Quota can overflow max uint256
   * 2. If you have an unexpired beneficiary address and have a quota, you should be rejected
   * 3. If you have an unexpired beneficiary address and have no quota left, you should be accepted. However, this call will still reject you because you have an unexpired beneficiary address. Once the quota is used up on the Miner Actor, even with an unexpired beneficiary, the miner's owner can reset the beneficiary address, essentially expiring it. This allows us to avoid the potential overflows on quota and not read them, also saves gas and code size
   *
   * It is not necessary to check the pending beneficiary as it will be reset
   * when ownership changes: https://github.com/filecoin-project/builtin-actors/blob/f28bfd0339ea51479efc5697eefffaddf5e9c244/actors/miner/src/lib.rs#L418
   */
  function configuredForTakeover(uint64 target) internal returns (bool) {
    CommonTypes.FilActorId minerId = _getMinerId(target);
    MinerTypes.GetBeneficiaryReturn memory ret = MinerAPI.getBeneficiary(minerId);

    // if the beneficiary address is the miner's owner, then the agent will assume beneficiary
    if (_getOwner(minerId) == PrecompilesAPI.resolveAddress(ret.active.beneficiary)) {
      return true;
    }

    // if the beneficiary address is expired, then Agent will be ok to take ownership
    MinerTypes.BeneficiaryTerm memory term = ret.active.term;
    uint256 expiration = uint256(uint64(CommonTypes.ChainEpoch.unwrap(term.expiration)));
    if (expiration < block.number) return true;

    return false;
  }

  /**
   * @param target The miner actor id you want to interact with
   * @param addr New owner address
   * @notice Proposes or confirms a change of owner address.
   * @notice If invoked by the current owner, proposes a new owner address for confirmation. If the proposed address is the current owner address, revokes any existing proposal that proposed address.
   */
  function changeOwnerAddress(uint64 target, address addr) internal {
    changeOwnerID(target, PrecompilesAPI.resolveEthAddress(addr));
  }

  /**
   * @param target The miner actor id you want to interact with
   * @param newOwner New owner ID address
   * @notice Proposes or confirms a change of owner address.
   * @notice If invoked by the current owner, proposes a new owner address for confirmation. If the proposed address is the current owner address, revokes any existing proposal that proposed address.
   */
  function changeOwnerID(uint64 target, uint64 newOwner) internal {
    MinerAPI.changeOwnerAddress(
      _getMinerId(target),
      FilAddresses.fromActorID(newOwner)
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
  ) internal {
    // resolve the controllers
    CommonTypes.FilAddress[] memory controllers = new CommonTypes.FilAddress[](controllerAddrs.length);
    for (uint256 i = 0; i < controllerAddrs.length; i++) {
      controllers[i] = FilAddresses.fromActorID(controllerAddrs[i]);
    }

    MinerAPI.changeWorkerAddress(
      _getMinerId(target),
      MinerTypes.ChangeWorkerAddressParams(
        FilAddresses.fromActorID(workerAddr),
        controllers
      )
    );
  }

  /**
   * @notice Confirms changing the worker address for a miner
   * @param target The miner actor id you want to interact with
   */
  function confirmChangeWorkerAddress(
    uint64 target
  ) internal {
    MinerAPI.confirmChangeWorkerAddress(_getMinerId(target));
  }

  /**
   * @param target The miner actor id you want to interact with
   * @param amount the amount you want to withdraw
   *
   * @dev here we pack the amount into bytes and then pass it to the BigInt constructor
   */
  function withdrawBalance(uint64 target, uint256 amount)
    internal
  {
    MinerAPI.withdrawBalance(
      _getMinerId(target),
      BigInts.fromUint256(amount)
    );
  }

  function _getMinerId(uint64 target) internal pure returns (CommonTypes.FilActorId) {
    return CommonTypes.FilActorId.wrap(target);
  }

  function _getOwner(CommonTypes.FilActorId minerId) internal returns (uint64) {
    return PrecompilesAPI.resolveAddress(MinerAPI.getOwner(minerId).owner);
  }

  /// @dev None of the numbers we use according to Filecoin spec can overflow max uint256
  /// largest number can be 2 billion attofil
  function _toUint256(CommonTypes.BigInt memory self) internal view returns (uint256 value) {
    (value, ) = self.toUint256();
  }
}
