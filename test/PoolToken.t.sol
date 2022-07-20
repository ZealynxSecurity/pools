// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/PoolToken.sol";

contract PoolTokenTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);
    address redmond = address(0x3);

    PoolToken poolToken;
    function setUp() public {
        poolToken = new PoolToken();
    }

    function testName() public {
        assertEq(poolToken.name(), "PoolToken");
    }

    function testSymbol() public {
      assertEq(poolToken.symbol(), "P0GLIF");
    }

    function testMinter() public {
      assertEq(poolToken.minter(), address(0));
      poolToken.setMinter(address(this));
      assertEq(poolToken.minter(), address(this));
    }

    function testInitialSupply() public {
      assertEq(poolToken.totalSupply(), 0);
    }

    function testBalanceOfDeployerIsZero() public {
      assertEq(poolToken.balanceOf(address(this)), 0);
    }

    function testMintTokensToDeployer() public {
      uint256 newTokens = 1000;
      poolToken.setMinter(address(this));
      poolToken.mint(address(this), newTokens);
      assertEq(poolToken.balanceOf(address(this)), newTokens);
      assertEq(poolToken.totalSupply(), newTokens);
    }

    function testMintTokensToBob() public {
      uint256 newTokens = 1000;
      poolToken.setMinter(address(this));
      poolToken.mint(bob, newTokens);
      assertEq(poolToken.balanceOf(address(this)), 0);
      assertEq(poolToken.balanceOf(bob), newTokens);
      assertEq(poolToken.totalSupply(), newTokens);
    }

    function testTransferTokens() public {
      uint256 newTokens = 1000;
      poolToken.setMinter(address(this));
      poolToken.mint(bob, newTokens);
      vm.startPrank(bob);
      poolToken.transfer(alice, 100);
      assertEq(poolToken.balanceOf(bob), 900);
      assertEq(poolToken.balanceOf(alice), 100);
    }

    function testBurnTokens() public {
      uint256 newTokens = 1000;
      poolToken.setMinter(address(this));
      poolToken.mint(address(this), newTokens);
      poolToken.burn(address(this), 500);
      assertEq(poolToken.balanceOf(address(this)), 500);
    }
}
