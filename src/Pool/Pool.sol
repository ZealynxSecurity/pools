// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Pool/PoolToken.sol";


interface IPool {
  function name() external view returns (string memory);
  function id() external view returns (uint256);
  function initialTokenPrice() external view returns (uint256);
  function tokenPrice() external view returns (uint256);
  function staked() external view returns (uint256);
  function rewards() external view returns (uint256);
  function assets() external view returns (uint256);
  function owed() external view returns (uint256);
  function repaymentAmount(uint256 amount) external view returns (uint256);
  function initialize(address _poolToken, uint256 _poolID) external;
  function poolToken() external view returns (address);
  function stake(address _staker) external payable returns (uint256);
  function paydownDebt(address _borrower) external payable returns (uint256);
  function exit(address exitTo, uint256 tokenAmount) external returns (uint256);
  function takeLoan(uint256 amount) external returns (uint256);
}

// everybody can mint an equal amount of credit from this pool (dumb pool)
contract Pool is IPool {
  string public name;
  uint256 public initialTokenPrice;
  uint256 public id;
  address public poolToken;

  uint256 public staked = 0;
  uint256 public rewards = 0;
  uint256 public assets = 0;
  uint256 public owed = 0;
  uint256 public fixedCreditAmount = 1 ether;

  uint256 public costOfCapital = 10;

  mapping(address => uint256) public _loans;

  constructor(uint256 _initialTokenPrice, string memory _name) {
    initialTokenPrice = _initialTokenPrice;
    name = _name;
  }

  function initialize(address _poolToken, uint256 _poolID) external {
    poolToken = _poolToken;
    id = _poolID;
  }

  function repaymentAmount(uint256 amount) public view returns (uint256) {
    return amount + (amount/costOfCapital);
  }

  function tokenPrice() public view returns (uint256) {
    if (assets == 0) return initialTokenPrice;
    return (assets)/PoolToken(poolToken).totalSupply();
  }

  function stake(address _staker) external payable returns(uint256) {
    require(msg.value > 0);
    uint256 tokensToMint = msg.value / tokenPrice();
    PoolToken(poolToken).mint(_staker, tokensToMint);
    staked += msg.value;
    assets += msg.value;
    return tokensToMint;
  }

  // burns your tokens for FIL at the current buy-in token price
  function exit(address exitTo, uint256 tokenAmount) public returns (uint256) {
    require(tokenAmount <= PoolToken(poolToken).balanceOf(msg.sender));
    // TODO: do this in the uniswap-y way where you take the tokenPrice at the end (or the geometric mean)
    uint256 valInFil = tokenPrice() * tokenAmount;
    // TODO: don't use the balance (we need to keep track of how much FIL we have on hand)
    require(address(this).balance >= valInFil);
    PoolToken(poolToken).burn(msg.sender, tokenAmount);
    payable(exitTo).transfer(valInFil);
    return valInFil;
  }

  function takeLoan(uint256 amount) external returns(uint256) {
    if (amount > staked + rewards) {
      return 0;
    }
    require(_loans[msg.sender] == 0);
    require(address(this).balance >= amount);

    uint256 repay = repaymentAmount(amount);
    owed += repay;
    _loans[msg.sender] = repay;
    assets += repay - amount;

    payable(address(msg.sender)).transfer(amount);

    return repay;
  }

  function paydownDebt(address _borrower) external payable returns(uint256) {
    // TODO: think about a more intelligent way to handle over payments
    require(msg.value > 0 && msg.value <= _loans[_borrower]);
    rewards += msg.value;
    owed -= msg.value;
    _loans[_borrower] -= msg.value;
    return _loans[_borrower];
  }
}
