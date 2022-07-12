// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// a tranche answers the question: - how much credit can this miner mint?
interface Tranche {
  // mints tTokens to caller (loan agent) and returns the amount of new tTokens that were minted
  function mint() external returns (uint256);
  // returns the amount of tokens this miner can mint at the current epoch
  function check() external view returns (uint256);
  // a mechanism for reducing debt in the system
  function burn(uint256 amount) external returns (uint256);
}
