// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Tranche/Tranche.sol";
import "src/TToken/TToken.sol";

contract TrancheTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);
    address redmond = address(0x3);

    uint256 initialTokenPrice = 1 ether;

    TToken tToken;
    Tranche tranche;
    function setUp() public {
        tToken = new TToken();
        tranche = new Tranche(initialTokenPrice, address(tToken));
        tToken.setMinter(address(tranche));
        vm.deal(bob, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(redmond, 10 ether);
    }

    // when no contributions are made and no rewards are earned, the tranche should have a fixed buy-in token price
    function testInitialTokenPrice() public {
        assertEq(tranche.initialTokenPrice(), initialTokenPrice);
    }

    // a wallet should be able to contribute FIL and receive tokens back at the initialTokenPrice
    function testInitialStake() public {
        uint256 stakeAmount = 10 ether;
        vm.startPrank(bob);
        uint256 tokensMinted = tranche.stake{value: stakeAmount}(bob);
        uint256 tokenBalance = tToken.balanceOf(bob);
        assertEq(tokensMinted, tokenBalance);
    }

    // function testTakeLoan() public {
    //     // bob is the investor, stakes 10 FIL
    //     uint256 stakeAmount = 10 ether;
    //     vm.startPrank(bob);
    //     tranche.stake{value: stakeAmount}(bob);
    //     vm.stopPrank();

    //     // alice is a miner who wants to take loan
    //     uint256 loanAmount = 2 ether;
    //     vm.startPrank(alice);
    //     uint256 amount = tranche.takeLoan(alice, loanAmount);
    //     assertEq(loanAmount, amount);
    // }

    // function testInitialRewards() public {
    //     uint256 stakeAmount = 10;
    //     vm.startPrank(bob);
    //     tranche.stake{value: stakeAmount}(bob);
    //     uint256 tokenBalance = tToken.balanceOf(bob);
    //     assertEq(tokenBalance, 10);
    // }

    //
}
