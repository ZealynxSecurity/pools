// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Tranche/Tranche.sol";
import "src/TToken/TToken.sol";

/**
 The stupid, simple tranche
 - Everyone can take a loan if they currently have no loans owed
 - The price is calculated by current ((stake + expected rewards) / total shares)
 - The price does not change (yet) based on finding out about a defaulted loan

 */
contract TrancheTest is Test {
    address bob = address(0x1);
    address alice = address(0x2);

    uint256 initialTokenPrice = 1 ether;

    TToken tToken;
    Tranche tranche;
    function setUp() public {
        tToken = new TToken();
        tranche = new Tranche(initialTokenPrice, address(tToken));
        tToken.setMinter(address(tranche));
        vm.deal(bob, 10 ether);
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

    function testRepaymentAmount() public {
        uint256 loanAmount = 10 ether;
        uint256 loanAmountWRepayment = tranche.repaymentAmount(loanAmount);
        assertEq(loanAmountWRepayment, 11 ether);
    }

    function mockStake() internal {
        // bob is the investor, stakes 10 FIL
        uint256 stakeAmount = 10 ether;
        vm.startPrank(bob);
        tranche.stake{value: stakeAmount}(bob);
        vm.stopPrank();
    }

    function mockLoan(uint256 loanAmount) public returns (uint256) {
        // alice is a miner who wants to take loan
        vm.prank(alice);
        return tranche.takeLoan(alice, loanAmount);
    }

    function testTakeLoan() public {
        mockStake();
        uint256 loanAmount = 2 ether;
        uint256 repayAmount = mockLoan(loanAmount);
        assertEq(tranche.repaymentAmount(loanAmount), repayAmount);
        assertEq(address(alice).balance, loanAmount);
    }

    function testReceiveRewards() public {
        mockStake();
        uint256 loanAmount = 2 ether;
        uint256 paybackAmount = 1 ether;
        mockLoan(loanAmount);
        uint256 remainingPaybackAmount = tranche.paydownDebt{value: paybackAmount}(alice);
        assertEq(tranche.repaymentAmount(loanAmount) - paybackAmount, remainingPaybackAmount);
    }

    function testTokenPriceChange() public {
        uint256 initialPrice = tranche.tokenPrice();
        mockStake();
        uint256 postStakePrice = tranche.tokenPrice();
        assertEq(initialPrice, postStakePrice);
        uint256 loanAmount = 2 ether;
        mockLoan(loanAmount);
        uint256 postLoanPrice = tranche.tokenPrice();
        // price goes up when a loan gets taken
        assertGt(postLoanPrice, initialPrice);
    }

    function testExit() public {
        address redmond = address(0x3);

        mockStake();
        uint256 loanAmount = 2 ether;
        mockLoan(loanAmount);
        tranche.paydownDebt{value: 2.2 ether}(alice);
        assertEq(tranche.owed(), 0);

        vm.startPrank(bob);
        uint256 filReturns = tranche.exit(redmond, tToken.balanceOf(bob));
        assertEq(redmond.balance, filReturns);
    }
}
