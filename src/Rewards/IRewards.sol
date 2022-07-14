// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

// receives rewards from a loan agent
interface Rewards {
  // returns how much FIL was distributed to the transmuter and how much is reinvested in the tranche by buying tTokens off the open market (auto compound)
  function distribute(uint256 amount) external returns (uint256, uint256);
}

// is debt denominated in tToken or in FIL?
// how does the transmuter handle "bad debt"?



/**
  OTC bootstrap (simplified example with no swap actor)
  1 investor and 1 miner and they make OTC deals together

  the fixed OTC price of tToken/FIL:
  - 1 FIL = 1.1 tToken
  - 1 tToken = .9 FIL

  t=0:
    - Miner: 0 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 0 FIL
    - Investor: 900 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 0k

  miner mints 1000 tTokens as credit (miner calls `mint` on the loan agent)
  t=1:
    - Miner: 0 FIL, 0 tTokens
    - Loan agent: 0 FIL, 1000 tTokens, debt: 1000 FIL
    - Investor: 900 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 1k

  miner swaps 1000 tTokens at fixed OTC price with investor and pledges
  investor immediately stakes 1000 tTokens in the transmuter
  t=2:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 1000 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 0 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  miner gets 1000 FIL in rewards and is available to withdraw
  t=3:
    - Miner: 1900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 1000 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 0 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  miner calls `paydownDebtFromRewards` on loan agent,
  which withdraws the funds from the miner actor and sends them to the transmuter
  t=4:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 0 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 1000 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  investor calls `claim` on the transmuter
  t=5:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 0 FIL
    - Investor: 1000 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 0
 */

/**
  OTC bootstrap (simplified example with no swap actor)
  1 investor and 1 miner and they make OTC deals together

  the fixed OTC price of tToken/FIL:
  - 1 FIL = 1.1 tToken
  - 1 tToken = .9 FIL

  t=0:
    - Miner: 0 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 0 FIL
    - Investor: 900 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 0k

  miner mints 1000 tTokens as credit (miner calls `mint` on the loan agent)
  t=1:
    - Miner: 0 FIL, 0 tTokens
    - Loan agent: 0 FIL, 1000 tTokens, debt: 1000 FIL
    - Investor: 900 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 1k

  miner swaps 1000 tTokens at fixed OTC price with investor and pledges
  investor immediately stakes 1000 tTokens in the transmuter
  t=2:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 1000 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 0 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  miner gets 100 FIL in rewards and is available to withdraw
  t=3:
    - Miner: 1000 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 1000 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 0 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  miner calls `paydownDebtFromRewards` on loan agent,
  which withdraws the funds from the miner actor and sends them to the transmuter
  t=4:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 900 FIL
    - Investor: 0 FIL, 0 tTokens, 1000 staked tTokens
    - Transmuter: 100 FIL, 1000 tTokens
    - tToken circulating supply: 1k

  investor calls `claim` on the transmuter
  t=5:
    - Miner: 900 FIL, 0 tTokens
    - Loan agent: 0 FIL, 0 tTokens, debt: 0 FIL
    - Investor: 1000 FIL, 0 tTokens, 0 staked tTokens
    - Transmuter: 0 FIL, 0 tTokens
    - tToken circulating supply: 0









Initially expect 2000 FIL in rewards
2000 total tTokens staked
100 FIL in the transmuter
emergency event - no more FIL expected (big miner default)
investorA has 1000 tTokens
investorB has 1000 tTokens

investorA claims to get his half (50 FIL)
how many tokens to burn?




50 FIL in the transmuter
1000 tokens are staked

Time weighted pro-rata distribution:
- your share is the time you spent staking * the amount you staked
- total pool = the total time of everyone thats been staking * the total rewards that came in
-





 */

 /**
  Transmuter as an investment pool

  t=0
  - Miner mints 100 tToken
  - investment pool => 0 FIL
  - rewards pool => 0 FIL

  t=1
  InvestorA puts in 100 FIL
  Assume 1FIL = 1tToken
  InvestorA gets 100 tTokens





  InvestorA ownership % = investment / (investment pool + reward pool)



  */






/**
  With swap actor

  tToken = future FIL

  t=0:
    - LP: 9k FIL, 10k tTokens (1 FIL = 1.11 tToken OR 1 tToken = .9 FIL)
    - Miner: 0 FIL, 0 tTokens
    - GLIF: 0 FIL, 0 tTokens
    - Rewards: 0 FIL, 0 tTokens
    - Investor: 1000 FIL, 0 tTokens
    - tToken circulating supply: 10k

  miner mints 1000 tTokens as credit (miner calls `mint` on the loan agent)
  t=1:
    - LP: 9k FIL, 10k tTokens (1 FIL = 1.11 tToken OR 1 tToken = .9 FIL)
    - Miner: 0 FIL, 1000 tTokens
    - GLIF: 0 FIL, 10 tTokens
    - Rewards: 0 FIL, 0 tTokens
    - VC: -9k FIL, -10k tTokens
    - tToken circulating supply: 11,010

  miner exchanges 1000 tTokens for 900 FIL via the swap actor (miner calls `takeLoan` on the loan agent)
  t=2:
    - LP: 8.1k FIL, 11k tTokens (1 FIL = 1.358 tToken OR 1 tToken = 0.736 FIL)
    - Miner: 900 FIL, 0 tTokens
    - GLIF: 0 FIL, 10 tTokens
    - Rewards: 0 FIL, 0 tTokens
    - tToken circulating supply: 11,010

  miner gets 1000 FIL in rewards and calls `paydownDebtFromRewards`
  t=3:
    - (Beginning) LP: 8.1k FIL, 11k tTokens (1 FIL = 1.358 tToken OR 1 tToken = 0.736 FIL)
    - Miner: 900 FIL, 0 tTokens
    - GLIF: 0 FIL, 10 tTokens
    - Rewards: 1000 FIL, 0 tTokens
    - tToken circulating supply: 11,010

  rewards actor exchanges the 1000 FIL for tTokens on the open market
    - LP: 9.1k FIL, 9,642 tTokens (1 FIL = 1.059 tToken OR 1 tToken = 0.94 FIL)
    - Miner: 900 FIL, 0 tTokens
    - GLIF: 0 FIL, 10 tTokens
    - Rewards: 0 FIL, 1,358 tTokens
    - tToken circulating supply: 11,010
    -



 */
