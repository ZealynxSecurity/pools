// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

interface IAuth {
  function owner() external view returns (address);
  function pendingOwner() external view returns (address);
  function transferOwnership(address newOwner) external;
  function acceptOwnership() external;

  function operator() external view returns (address);
  function pendingOperator() external view returns (address);
  function transferOperator(address newOperator) external;
  function acceptOperator() external;

  function checkOwnerOperator() external view;
}
