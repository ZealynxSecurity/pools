// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

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
