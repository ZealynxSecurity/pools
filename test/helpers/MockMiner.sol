// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";

struct GetBeneficiaryReturn {
  ActiveBeneficiary active;
  PendingBeneficiaryChange proposed;
}

struct BeneficiaryTerm {
  uint256 quota;
  uint256 used_quota;
  uint64 expiration;
}

struct ActiveBeneficiary {
  uint64 beneficiary;
  BeneficiaryTerm term;
}

struct PendingBeneficiaryChange {
  uint64 new_beneficiary;
  uint256 new_quota;
  uint64 new_expiration;
  bool approved_by_beneficiary;
  bool approved_by_nominee;
}

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
    if (maxSend < amount) amount = maxSend;

    // interact
    (bool success, ) = payable(address(owner)).call{value: amount}("");
    require(success, "transfer failed");

    return amount;
  }

  function setID(uint64 _id) external {
    id = _id;
  }
}
