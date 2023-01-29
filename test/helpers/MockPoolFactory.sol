// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {RouterAware} from "src/Router/RouterAware.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";

contract PoolFactory is IPoolFactory, RouterAware {
  uint256 public constant MAX_TREASURY_FEE = 1e17;
  uint256 public treasuryFeeRate;
  uint256 public feeThreshold;
  IERC20 public asset;
  address[] public allPools = [address(0)];
  // poolExists
  mapping(bytes32 => bool) public exists;

  constructor(address _router) {
    router = _router;
  }

  function createSymbol() internal view returns (string memory) {
    return "P0GLIF";
  }

  function allPoolsLength() public view returns (uint256) {
    return 1;
  }

  function createPool(
    string memory name,
    string memory symbol,
    address operator,
    address implementation,
    address template
  ) external returns (IPool) {}

  function upgradePool(
    uint256
  ) external returns (IPool) {}

  function isPool(address pool) external view returns (bool) {
    return true;
  }

  function isPoolTemplate(address template) public view returns (bool) {
    return true;
  }

  function isPoolImplementation(address implementation) public view returns (bool) {
    return true;
  }

  function approveImplementation(address implementation) external {}

  function approveTemplate(address template) external {}

  function revokeImplementation(address implementation) external {}

  function revokeTemplate(address template) external {}

  function setTreasuryFeeRate(uint256 newFeeRate) external {}

  function setFeeThreshold(uint256 newThreshold) external {}
}
