# WELCOME TO GLIF POOLS

Alleviating Filecoin's capital inefficiences through a novel Filecoin leasing protocol.

This is the GLIF Pools smart contracts repo.

In this project, we have conducted tests on several key functionalities. In the "test/echidna" folder, you will find three important files:

- EchidnaAgent.sol
- EchidnaInfinityPoolV2.sol
- EchidnaLiquidityMineLP.sol

These files contain systematically organized tests for different contracts in the project. Each focuses on a specific aspect of functionality, ensuring comprehensive coverage.

Next, we will provide detailed instructions for:

- Installing all necessary dependencies.
- Running each of the tests individually.

These instructions will allow you to replicate our testing environment and verify the results yourself, ensuring transparency and reproducibility of our testing processes.

| Section                                             | Description                                |
| --------------------------------------------------- | ------------------------------------------ |
| [Installation](#installation)                       | Setup and installation requirements.       |
| [Init](#init)                                       | Initial setup and build commands.          |
| [Where to Find the Tests](#where-to-find-the-tests) | Locations of different test suites.        |
| [Testing Environments](#testing-environments)       | Overview of testing environments: Echidna. |
| [Echidna Tests](#echidna)                           | Setup and execution of Echidna tests.      |
| [Test Cases](#test-cases)                           | Test Cases.                                |

## Installation

To be able to use this repository, you need to have the following installed:

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Echidna](https://github.com/crytic/echidna?tab=readme-ov-file#installation)

## Init:

```js
 git submodule update --init --recursive
```

```js
sudo forge build -force
```

## Where to find the tests

You can find the tests in various folders:

- Echidna in the `test/echidna/EchidnaAgent.sol` folder
- Echidna in the `test/echidna/EchidnaInfinityPoolV2.sol` folder
- Echidna in the `test/echidna/EchidnaLiquidityMineLP.sol` folder

# Testing Environments

## Echidna

### Resources to set up environment and understand approach

- [Documentation](https://secure-contracts.com/index.html)
- [Properties](https://github.com/crytic/properties)
- [echidna](https://github.com/crytic/echidna)
- [Echidna Tutorial: #2 Fuzzing with Assertion Testing Mode](https://www.youtube.com/watch?v=em8xXB9RHi4&ab_channel=bloqarl)
- [Echidna Tutorial: #1 Introduction to create Invariant tests with Solidity](https://www.youtube.com/watch?v=yUC3qzZlCkY&ab_channel=bloqarl)
- [Echidna Tutorial: Use Echidna Cheatcodes while Fuzzing](https://www.youtube.com/watch?v=SSzh5GlqteI&ab_channel=bloqarl)

### Where are tests

- Echidna in the `test/echidna/EchidnaAgent.sol` folder
- Echidna in the `test/echidna/EchidnaInfinityPoolV2.sol` folder
- Echidna in the `test/echidna/EchidnaLiquidityMineLP.sol` folder

### How to run them

#### EchidnaAgent

- `test/echidna/EchidnaAgent.sol`

```solidity
 echidna . --contract EchidnaAgent --config config.yaml
```

#### EchidnaInfinityPoolV2

- `test/echidna/EchidnaInfinityPoolV2.sol`

```solidity
 echidna . --contract EchidnaInfinityPoolV2 --config config.yaml
```

#### EchidnaLiquidityMineLP

- `test/echidna/EchidnaLiquidityMineLP.sol`

```solidity
 echidna . --contract EchidnaLiquidityMineLP --config config.yaml
```

## Test Cases

TOTAL 52

#### `test/echidna/EchidnaAgent.sol`

| #   | Property                                                   | Tested                                            | Pass |
| --- | ---------------------------------------------------------- | ------------------------------------------------- | ---- |
| 1   | echtest_agent_borrow                                       | borrow from pool                                  | ✅   |
| 2   | echtest_agent_borrow_invalid_params                        | borrow with invalid parameters                    | ✅   |
| 3   | echtest_agent_borrow_not_owner                             | borrow by non-owner                               | ✅   |
| 4   | echtest_agent_borrow_expired_credential                    | borrow with expired credential                    | ✅   |
| 5   | echtest_agent_borrow_invalid_signature                     | borrow with invalid signature                     | ✅   |
| 6   | echtest_consecutive_borrows_update_liquid_assets           | update assets after consecutive borrows           | ✅   |
| 7   | echtest_agent_borrow_fails_with_reused_credential          | borrow fails with reused credential               | ✅   |
| 8   | echtest_agent_borrow_rewards                               | rewards distribution after borrow                 | ✅   |
| 9   | echtest_agent_borrow_update_accounting                     | update accounting after borrow                    | ✅   |
| 10  | echtest_agent_borrow_paused                                | borrow when pool is paused                        | ✅   |
| 11  | echtest_pay_interest_only                                  | pay interest only                                 | ✅   |
| 12  | echtest_pay_full_repayment                                 | pay full loan repayment                           | ✅   |
| 13  | echtest_nonAgentCannotPay                                  | unauthorized payment attempt                      | ✅   |
| 14  | echtest_cannotPayOnNonExistentAccount                      | payment on non-existent account                   | ✅   |
| 15  | echtest_distributeLiquidatedFundsPartialRecoveryNoInterest | distribute liquidated funds with partial recovery | ✅   |
| 16  | echtest_agentLoanAndLiquidationProcess                     | complete loan and liquidation process             | ✅   |

#### `test/echidna/EchidnaInfinityPoolV2.sol`

| #   | Property                                                | Tested                                                  | Pass |
| --- | ------------------------------------------------------- | ------------------------------------------------------- | ---- |
| 1   | echtest_deposit_wFIL                                    | deposit with wrapped FIL                                | ✅   |
| 2   | echtest_deposit_FIL                                     | deposit with native FIL                                 | ✅   |
| 3   | echtest_wFILTotalSupplyInvariant                        | wrapped FIL total supply invariant                      | ✅   |
| 4   | echtest_zeroDepositReverts                              | zero deposit reversion                                  | ✅   |
| 5   | echtest_exceedingInvestorBalanceReverts                 | deposit exceeding balance reversion                     | ✅   |
| 6   | echtest_correctSharesAfterSecondDeposit                 | correct shares after second deposit                     | ✅   |
| 7   | echtest_investorSharesBalanceAfterDeposits              | investor shares balance after multiple deposits         | ✅   |
| 8   | echtest_previewDepositRoundingError                     | preview deposit rounding error                          | ✅   |
| 9   | echtest_tokenMintingOnDeposit                           | token minting on deposit                                | ✅   |
| 10  | echtest_depositRevertsWhenPaused                        | deposit reversion when paused                           | ✅   |
| 11  | echtest_depositRevertsWithInvalidReceiver               | deposit reversion with invalid receiver                 | ✅   |
| 12  | echtest_multipleConsecutiveDeposits                     | multiple consecutive deposits                           | ✅   |
| 13  | echtest_successfulWithdrawal                            | successful withdrawal                                   | ✅   |
| 14  | echtest_withdrawalAlternativeRecipient                  | withdrawal with alternative recipient                   | ✅   |
| 15  | echtest_withdrawUpdatesAccounting                       | withdrawal updates accounting                           | ✅   |
| 16  | echtest_withdrawRevertsOnInsufficientApprovedLiquidity  | withdrawal reversion on insufficient approved liquidity | ✅   |
| 17  | echtest_withdrawRevertsWithInvalidReceiver              | withdrawal reversion with invalid receiver              | ✅   |
| 18  | echtest_withdrawRevertsWhenPaused                       | withdrawal reversion when paused                        | ✅   |
| 19  | echtest_multipleConsecutiveWithdrawals                  | multiple consecutive withdrawals                        | ✅   |
| 20  | echtest_withdrawFRevertsWhenPaused                      | withdrawF reversion when paused                         | ✅   |
| 21  | echtest_withdrawFRevertsWithInvalidReceiver             | withdrawF reversion with invalid receiver               | ✅   |
| 22  | echtest_withdrawFRevertsOnInsufficientApprovedLiquidity | withdrawF reversion on insufficient approved liquidity  | ✅   |

#### `test/echidna/EchidnaLiquidityMineLP.sol`

| #   | Property                              | Tested                                       | Pass |
| --- | ------------------------------------- | -------------------------------------------- | ---- |
| 1   | echtest_locked_tokens_increase        | increase in locked tokens after deposit      | ✅   |
| 2   | echtest_unclaimed_rewards_calculation | calculation of unclaimed rewards             | ✅   |
| 3   | echtest_reward_debt_calculation       | calculation of reward debt                   | ✅   |
| 4   | echtest_deposit_transfer_successful   | successful token transfer on deposit         | ✅   |
| 5   | echtest_locked_tokens_decrease        | decrease in locked tokens after withdrawal   | ✅   |
| 6   | echtest_unclaimed_rewards_update      | update of unclaimed rewards after withdrawal | ✅   |
| 7   | echtest_reward_debt_update            | update of reward debt after withdrawal       | ✅   |
| 8   | echtest_withdraw_transfer_successful  | successful token transfer on withdrawal      | ✅   |
| 9   | echtest_harvest_rewards_update        | update of rewards after harvesting           | ✅   |
| 10  | echtest_reward_debt_after_harvest     | reward debt calculation after harvesting     | ✅   |
| 11  | echtest_withdraw_and_harvest_basic    | basic withdraw and harvest functionality     | ✅   |
| 12  | echtest_multiple_deposits_accrual     | reward accrual with multiple deposits        | ✅   |
| 13  | echtest_reward_cap_exceeded           | behavior when reward cap is exceeded         | ✅   |
| 14  | echtest_set_reward_per_epoch          | setting new reward per epoch                 | ✅   |
