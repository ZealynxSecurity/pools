// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "src/Pool/PoolToken.sol";
import "src/Pool/Pool.sol";

interface IPoolFactory {
  function allPools(uint256 poolID) external view returns (address);
  function allPoolsLength() external view returns (uint256);
  function create(address pool) external returns (uint256, address);
}

contract PoolFactory is Ownable {
  address[] public allPools;

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

  function create(address pool) external onlyOwner returns (uint256 poolID, address poolTokenAddress) {
    poolID = allPools.length;
    PoolToken poolToken = new PoolToken(
      IPool(address(pool)).name(),
      createSymbol(),
      address(pool)
    );
    poolTokenAddress = address(poolToken);
    IPool(address(pool)).initialize(address(poolToken), poolID);
    allPools.push(address(pool));
  }
}
