# Documentation for the Contract `LiquidityMineLP.sol`

The contract implements accrual basis accounting for rewards by:

1. Keeping track of how many GLIF tokens each locked token (iFIL) is worth
2. Creating atomic units of time where the accounting of the system is consistent, which gets updated on every external call of the contract. Every time a user deposits, harvests rewards, or withdraws iFIL from the liquidity mine contract, the accounting of the system updates

The liquidity mine is funded with GLF tokens, unlike masterchef, it is not a minter of GLIF tokens. There's an associated "cap" of max rewards that the contract will eventually disperse, which can be updated by the owner

Basically, as long as:

- there is at least 1 wei of locked tokens (iFIL) in the contract
- the liquidity mine contract is funded with reward tokens (GLF)
- the liquidity mine contract has not already accrued all of its "capped" rewards in distributions to users

Then stakers who have put iFIL in the liquidity mine contract will accrue rewards every block. There is a fixed amount of GLF tokens that are "distributed" in each block. "Distributed" is in quotes because tokens are not necessarily transferred out of the contract, rather they accrue to the accounts

The heart of the accrual based accounting logic lives in the internal \_computeAccRewards function

The main logic there is:

- Depending on the amount of iFIL tokens staked in the LM contract, each iFIL token accrues GLF tokens each block. The accRewardsPerLockToken tracks this amount, and this number should only ever increase
- accRewardsTotal tracks the total amoutn of accrued GLF distribution, and is mainly used to check against the totalRewardCap as to not over allocate rewards that the contract can't spend. This number should also only ever increase, and always be smaller than totalRewardCap

The UserInfo struct type keeps track of the per account accounting.

The most confusing variable in there is `rewardDebt`. In a way, you could think of `rewardDebt` as an amount of GLF tokens the staker actually owes the LM, with no expectation that it will pay those tokens back.

So the accounting works such that, you're always owed the:

`accRewardsPerLockToken * lockedTokens`

However, since the accRewardsPerLockToken may contain both (1) rewards you already claimed and (2) rewards that were accrued when you had 0 iFIL staked in the contract, the accounting uses rewardDebt to track both of these values

So when you compute the amount of tokens you're owed for a specific period of time, you can always do:

(`accRewardsPerLockToken * lockedTokens`) - rewardDebt to tell you how many tokens you've earned. Since accRewardsPerLockToken will increase and rewardDebt and lockedTokens don't change, then the tokens you earn for this period of accrual will be >0. So the contract will accrue the owed rewards to an unclaimedRewards bucket, and increase the rewardDebt to equal (`accRewardsPerLockToken * lockedTokens`) as to say the account is "up to date"

Of course the lockedTokens will change if the user deposits or withdraws iFIL, but that will trigger an accounting update beforehand.

These are some of the considered Invariants that should never be broken:

- The LM `accRewardsTotal` should always be less than or equal to `totalRewardCap`
- The LM `rewardTokensClaimed` should always be less than or equal `toaccRewardsTotal`
- The LM balanceOf GLF tokens + `rewardTokensClaimed` should always equal `totalRewardCap`
