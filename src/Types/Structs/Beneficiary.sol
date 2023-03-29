// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

struct Beneficiary {
  // the epoch in which this beneficiary is expired
  uint256 expiration;
  // the amount of FIL this beneficiary is allowed to withdraw
  uint256 quota;
  // the amount of FIL this beneficiary has withdrawn
  uint256 usedQuota;
  // the address of the beneficiary
  address beneficiary;
}

struct AgentBeneficiary {
  Beneficiary active;
  Beneficiary proposed;
}

library BeneficiaryHelpers {
  error Unauthorized();

  function isActive(AgentBeneficiary memory beneficiary) internal view returns (bool) {
    bool expired = beneficiary.active.expiration < block.number;
    bool hasUnusedQuota = beneficiary.active.usedQuota < beneficiary.active.quota;
    // if the beneficiary is not expired and it has unused quota, it's active
    return !expired && hasUnusedQuota;
  }

  function propose(
    AgentBeneficiary memory beneficiary,
    address newBeneficiary,
    uint256 quota,
    uint256 expiration
  ) internal pure returns (
    AgentBeneficiary memory
  ) {
    Beneficiary memory proposedBeneficiary = Beneficiary({
      expiration: expiration,
      quota: quota,
      usedQuota: 0,
      beneficiary: newBeneficiary
    });

    beneficiary.proposed = proposedBeneficiary;
    return beneficiary;
  }

  function approve(AgentBeneficiary memory beneficiary, address approver) internal pure returns (AgentBeneficiary memory) {
    if (beneficiary.proposed.beneficiary != approver) {
      revert Unauthorized();
    }

    beneficiary.active = beneficiary.proposed;
    beneficiary.proposed = Beneficiary(0, 0, 0, address(0));
    return beneficiary;
  }

  /// @dev `withdraw` returns the updated beneficiary structure, and the amount of FIL to withdraw (if withdrawing exceeds the unused quota)
  function withdraw(
    AgentBeneficiary memory beneficiary,
    uint256 amount
  ) internal pure returns (
    AgentBeneficiary memory updatedBeneficiary,
    uint256 withdrawAmount
  ) {
    uint256 unusedQuota = beneficiary.active.quota - beneficiary.active.usedQuota;

    withdrawAmount = amount;

    if (amount > unusedQuota) {
      withdrawAmount = unusedQuota;
    }
    beneficiary.active.usedQuota += withdrawAmount;
    return (beneficiary, withdrawAmount);
  }
}
