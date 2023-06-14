// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// import {RouterAware} from "src/Router/RouterAware.sol";
// import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
// import {IPool} from "src/Types/Interfaces/IPool.sol";
// import {IERC20} from "src/Types/Interfaces/IERC20.sol";

// contract PoolRegistry is IPoolRegistry, RouterAware {
//   uint256 public constant MAX_TREASURY_FEE = 1e17;
//   uint256 public treasuryFeeRate;
//   uint256 public feeThreshold;
//   IERC20 public asset;
//   address[] public allPools = [address(0)];
//   // poolExists
//   mapping(bytes32 => bool) public exists;

//   constructor(address _router) {
//     router = _router;
//   }

//   function createSymbol() internal view returns (string memory) {
//     return "P0GLIF";
//   }

//   function allPoolsLength() public view returns (uint256) {
//     return 1;
//   }

//   function createPool(
//     string memory name,
//     string memory symbol,
//     address owner,
//     address operator,
//     address implementation
//   ) external returns (IPool) {}

//   function upgradePool(
//     uint256
//   ) external returns (IPool) {}

//   function isPool(address pool) external view returns (bool) {
//     return true;
//   }

//   function isPoolImplementation(address implementation) public view returns (bool) {
//     return true;
//   }

//   function approveImplementation(address implementation) external {}

//   function revokeImplementation(address implementation) external {}

//   function setTreasuryFeeRate(uint256 newFeeRate) external {}

//   function setFeeThreshold(uint256 newThreshold) external {}
// }
