// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.15;

// import "forge-std/Test.sol";
// import "src/Pool/PoolFactory.sol";
// import "src/Pool/Pool.sol";
// import "src/Pool/PoolToken.sol";

// /**
//  The stupid, simple pool
//  - Everyone can take a loan if they currently have no loans owed
//  - The price is calculated by current ((stake + expected rewards) / total shares)
//  - The price does not change (yet) based on finding out about a defaulted loan

//  */
// contract PoolTest is Test {
//     address bob = address(0x1);
//     address alice = address(0x2);

//     string poolName = "FIRST POOL NAME";
//     uint256 initialTokenPrice = 1 ether;

//     PoolFactory poolFactory;
//     Pool pool;
//     PoolToken poolToken;
//     function setUp() public {
//         poolFactory = new PoolFactory();
//         pool = new Pool(initialTokenPrice, poolName);
//         (, address poolTokenAddress) = poolFactory.create(address(pool));
//         poolToken = PoolToken(poolTokenAddress);
//         vm.deal(bob, 10 ether);
//     }

//     // when no contributions are made and no rewards are earned, the pool should have a fixed buy-in token price
//     function testInitialTokenPrice() public {
//         assertEq(pool.initialTokenPrice(), initialTokenPrice);
//     }

//     // a wallet should be able to contribute FIL and receive tokens back at the initialTokenPrice
//     function testInitialStake() public {
//         uint256 stakeAmount = 10 ether;
//         vm.startPrank(bob);
//         uint256 tokensMinted = pool.stake{value: stakeAmount}(bob);
//         uint256 tokenBalance = poolToken.balanceOf(bob);
//         assertEq(tokensMinted, tokenBalance);
//     }

//     function testRepaymentAmount() public {
//         uint256 loanAmount = 10 ether;
//         uint256 loanAmountWRepayment = pool.repaymentAmount(loanAmount);
//         assertEq(loanAmountWRepayment, 11 ether);
//     }

//     function mockStake() internal {
//         // bob is the investor, stakes 10 FIL
//         uint256 stakeAmount = 10 ether;
//         vm.startPrank(bob);
//         pool.stake{value: stakeAmount}(bob);
//         vm.stopPrank();
//     }

//     function mockLoan(uint256 loanAmount) public returns (uint256) {
//         // alice is a miner who wants to take loan
//         vm.prank(alice);
//         return pool.takeLoan(loanAmount);
//     }

//     function testTakeLoan() public {
//         mockStake();
//         uint256 loanAmount = 2 ether;
//         uint256 repayAmount = mockLoan(loanAmount);
//         assertEq(pool.repaymentAmount(loanAmount), repayAmount);
//         assertEq(address(alice).balance, loanAmount);
//     }

//     function testReceiveRewards() public {
//         mockStake();
//         uint256 loanAmount = 2 ether;
//         uint256 paybackAmount = 1 ether;
//         mockLoan(loanAmount);
//         uint256 remainingPaybackAmount = pool.paydownDebt{value: paybackAmount}(alice);
//         assertEq(pool.repaymentAmount(loanAmount) - paybackAmount, remainingPaybackAmount);
//     }

//     function testTokenPriceChange() public {
//         uint256 initialPrice = pool.tokenPrice();
//         mockStake();
//         uint256 postStakePrice = pool.tokenPrice();
//         assertEq(initialPrice, postStakePrice);
//         uint256 loanAmount = 2 ether;
//         mockLoan(loanAmount);
//         uint256 postLoanPrice = pool.tokenPrice();
//         // price goes up when a loan gets taken
//         assertGt(postLoanPrice, initialPrice);
//     }

//     function testExit() public {
//         address redmond = address(0x3);

//         mockStake();
//         uint256 loanAmount = 2 ether;
//         mockLoan(loanAmount);
//         pool.paydownDebt{value: 2.2 ether}(alice);
//         assertEq(pool.owed(), 0);

//         vm.startPrank(bob);
//         uint256 filReturns = pool.exit(redmond, poolToken.balanceOf(bob));
//         assertEq(redmond.balance, filReturns);
//     }

//     function testRepayment() public {
//         mockStake();
//         uint256 loanAmount = 1 ether;
//         mockLoan(loanAmount);
//         uint256 paymentInterval = pool.paymentInterval();
//         // tell us the next epoch we need to make our next payment by to avoid penalties
//         (uint256 nextPaymentDeadlineEpoch, uint256 epochsLeft) = pool.getPaymentDeadlineEpoch(alice);
//         // tell us the minimum payment amount we need to make by the deadline epoch to avoid penalties
//         uint256 nextPaymentAmount = pool.getNextPaymentAmount(alice);
//         // roll blocks up to (but not past) the deadline epoch
//         vm.roll(paymentInterval - 5);
//         // make sure we don't have any penalties
//         uint256 penaltyAmount = pool.getPenalty(alice);
//         // paydown min amount
//         pool.paydownDebt{value: nextPaymentAmount}(alice);

//         // check that the nextPaymentDeadlineEpoch increases
//     }

//     // function testRepayment() public {
//     //     mockStake();
//     //     uint256 loanAmount = 1 ether;
//     //     mockLoan(loanAmount);
//     //     uint256 paymentInterval = pool.paymentInterval();
//     //     // tell us the next epoch we need to make our next payment by to avoid penalties
//     //     (uint256 nextPaymentDeadlineEpoch, uint256 epochsLeft) = pool.getPaymentDeadlineEpoch(alice);
//     //     // tell us the minimum payment amount we need to make by the deadline epoch to avoid penalties
//     //     uint256 nextPaymentAmount = pool.getNextPaymentAmount(alice);
//     //     // roll blocks up to (but not past) the deadline epoch
//     //     vm.roll(paymentInterval - 5);
//     //     // make sure we don't have any penalties
//     //     uint256 penaltyAmount = pool.getPenalty(alice);
//     //     // paydown min amount
//     //     pool.paydownDebt{value: nextPaymentAmount}(alice);
//     // }
// }
