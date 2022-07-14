// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/TToken/TToken.sol";

// everybody can mint from this tranche an equal amount of credit! yay!
contract Tranche {
  uint256 public initialTokenPrice;
  address public tToken;

  uint256 public totalFilDeposits = 0;
  uint256 public totalActiveLoans = 0;
  uint256 public totalFilRewards = 0;

  mapping(address => uint256) public _stakes;
  mapping(address => uint256) public _loans;

  constructor(uint256 _initialTokenPrice, address _tToken) {
    initialTokenPrice = _initialTokenPrice;
    tToken = _tToken;
  }

  function tokenPrice() public view returns (uint256) {
    if (totalFilDeposits == 0) return initialTokenPrice;
    return (totalFilDeposits + totalFilRewards)/TToken(tToken).totalSupply();
  }

  function stake(address _staker) external payable returns(uint256) {
    require(msg.value > 0);
    uint256 tokensToMint = msg.value / tokenPrice();
    TToken(tToken).mint(_staker, tokensToMint);
    totalFilDeposits += msg.value;
    return tokensToMint;
  }

  // function takeLoan(address _borrower, uint256 amount) external returns(uint256) {
  //   require(amount <= totalFilDeposits - totalActiveLoans);
  //   require(_loans[_borrower] == 0);
  // }
}
