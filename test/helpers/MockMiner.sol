// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {IMockMiner} from "test/helpers/IMockMiner.sol";
import "src/Types/Structs/Filecoin.sol";

contract MockMiner is IMockMiner {
  address public owner;
  address public proposed;
  uint64 public id;

  ActiveBeneficiary public activeBeneficiary;
  PendingBeneficiaryChange public proposedBeneficiary;

  constructor(
    address _owner
  ) {
    owner = _owner;
  }

  receive() external payable {}

  fallback() external payable {}


  /// @param newOwner New owner address
  /// @notice Proposes or confirms a change of owner address.
  /// @notice If invoked by the current owner, proposes a new owner address for confirmation. If the proposed address is the current owner address, revokes any existing proposal that proposed address.
  function changeOwnerAddress(address newOwner) external {
    if (msg.sender == owner) {
      proposed = newOwner;
    } else if (msg.sender == proposed && newOwner == proposed) {
      owner = proposed;
      proposed = address(0);
    } else {
      revert("not authorized");
    }
  }

  /// @notice This method is for use by other actors (such as those acting as beneficiaries), and to abstract the state representation for clients.
  /// @notice Retrieves the currently active and proposed beneficiary information.
  function getBeneficiary() external view returns (GetBeneficiaryReturn memory) {
    return GetBeneficiaryReturn({
      active: activeBeneficiary,
      proposed: proposedBeneficiary
    });
  }

  function changeWorkerAddress(uint64, uint64[] memory) external {
  }

  /// @param amount the amount you want to withdraw
  /// @return amountWithdrawn the amount that was actually withdrawn
  function withdrawBalance(uint256 amount) external returns (uint256 amountWithdrawn) {
    // check
    require(msg.sender == owner);
    uint256 maxSend = address(this).balance;
    require(amount <= maxSend);

    // effect
    if (amount == 0) {
      amountWithdrawn = maxSend;
    } else {
      amountWithdrawn = amount;
    }

    // interact
    (bool success, ) = payable(address(owner)).call{value: amountWithdrawn}("");
    require(success, "transfer failed");
  }

  function setID(uint64 _id) external {
    id = _id;
  }
}
