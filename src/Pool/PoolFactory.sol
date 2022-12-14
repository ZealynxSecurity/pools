// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "src/Pool/SimpleInterestPool.sol";
import "src/Pool/IPoolFactory.sol";
import "src/Router/RouterAware.sol";

contract PoolFactory is IPoolFactory, RouterAware {
  ERC20 public asset;
  address[] public allPools;
  address public treasury;

  constructor(ERC20 _asset, address _treasury) {
    asset = _asset;
    treasury = _treasury;
  }

  function createSymbol() internal view returns (string memory) {
    bytes memory b;
    b = abi.encodePacked("P");
    b = abi.encodePacked(b, Strings.toString(allPools.length));
    b = abi.encodePacked(b, "GLIF");

    return string(b);
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  function createSimpleInterestPool(string memory name, uint256 baseInterestRate) external returns (IPool4626 pool) {
    pool = new SimpleInterestPool(asset, name, createSymbol(), allPools.length, baseInterestRate, treasury, router);
    allPools.push(address(pool));
  }
}
