// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/TToken/TToken.sol";

contract TTokenTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);
    address redmond = address(0x3);

    TToken tToken;
    function setUp() public {
        tToken = new TToken();
    }

    function testName() public {
        assertEq(tToken.name(), "tToken");
    }

    function testSymbol() public {
      assertEq(tToken.symbol(), "TTK");
    }

    function testMinter() public {
      assertEq(tToken.minter(), address(0));
      tToken.setMinter(address(this));
      assertEq(tToken.minter(), address(this));
    }

    function testInitialSupply() public {
      assertEq(tToken.totalSupply(), 0);
    }

    function testBalanceOfDeployerIsZero() public {
      assertEq(tToken.balanceOf(address(this)), 0);
    }

    function testMintTokensToDeployer() public {
      uint256 newTokens = 1000;
      tToken.setMinter(address(this));
      tToken.mint(address(this), newTokens);
      assertEq(tToken.balanceOf(address(this)), newTokens);
      assertEq(tToken.totalSupply(), newTokens);
    }

    function testMintTokensToBob() public {
      uint256 newTokens = 1000;
      tToken.setMinter(address(this));
      tToken.mint(bob, newTokens);
      assertEq(tToken.balanceOf(address(this)), 0);
      assertEq(tToken.balanceOf(bob), newTokens);
      assertEq(tToken.totalSupply(), newTokens);
    }

    function testTransferTokens() public {
      uint256 newTokens = 1000;
      tToken.setMinter(address(this));
      tToken.mint(bob, newTokens);
      vm.startPrank(bob);
      tToken.transfer(alice, 100);
      assertEq(tToken.balanceOf(bob), 900);
      assertEq(tToken.balanceOf(alice), 100);
    }

    function testBurnTokens() public {
      uint256 newTokens = 1000;
      tToken.setMinter(address(this));
      tToken.mint(address(this), newTokens);
      tToken.burn(address(this), 500);
      assertEq(tToken.balanceOf(address(this)), 500);
    }
}
