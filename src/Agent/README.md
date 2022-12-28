# Agents and the Agent Police

## Agents

Agents are smart contracts that are the only elligible borrowers within the GLIF Pools protocol. An Agent collateralizes some value, which enables the Agent's owner/operator to borrow against that collateral from individual pools. In our V0 Agent, Filecoin Storage Providers are the _only_ valid form of collateral to stake into an Agent. However, in the near future, we expect other forms of accepteble collateral like stablecoins, alt-coins from other projects, and bridged tokens from other networks.

```
                     +-----------------------+
+-----------+        |       **AGENT**       |
|           |        |                       |
|   POOL1   | -----> |                       |
|           |        |+---------------------+|
+-----------+        ||        FSP1         ||
                     |+---------------------+|
+-----------+        |+---------------------+|
|           |        ||        FSP2         ||
|   POOL2   | -----> |+---------------------+|
|           |        |+---------------------+|
+-----------+        ||        FSP3         ||
                     |+---------------------+|
                     +-----------------------+
```

## Collateralizing a Filecoin Storage Provider (FSP)

In order to collateralize a FSP, the FSP's owner must assign ownership of the FSP to the Agent smart contract. So long as the predefined criteria are met [exact criteria TBD], the FSP can unassign ownership from the Agent at any time. An Agent can collateralize any number of FSPs.

## Valuing FSP Collateral

The value of a FSP as collateral depends on many factors, but there are two factors to pay close attention to:

1. The FSP's Liquidation Value - the value (denominated in FIL) the FSP's owner can expect to recoup after facing maximum slashing penalties
2. The FSP's Daily Expected Rewards - the value (denominated in FIL) of the FSP's expected earnings over the course of the next 24 hours

Both of these factors are estimates and require a 42 day forecast into the future to calculate. As the forecast moves through time in the future, the confidence level of the accuracy decreases, since changing conditions can happen along the way that can effect the end result.

With that in mind, the explicit "value" of FSP collateral is left up to the pools.

## Accounting for Limited Borrowing Potential - Minting Power Tokens

Since Pools must implement their own valuation techniques for FSP collateral, one responsibility of the Agent is to ensure finite borrowing power (Agents should not be able to endlessly borrow funds from hundreds of pools).

The Agent uses a Filecoin native metric - [Quality Adjusted Power (QAP)](https://spec.filecoin.io/systems/filecoin_mining/sector/sector-quality/) - to enforce limited borrowing capability by the agent. To do this, the Agent can mint Power ERC20 tokens up to the amount of quality adjusted power controlled by the Agent. For instance, if the Agent collateralizes 2 FSPs, both with 100 GiB of QAP, the Agent would be allowed to mint no more than 200 power tokens.

In order to borrow from a Pool, an Agent must stake power tokens. As a result, the Agent has limited borrowing power up to the amount of power the Agent can mint. Using the above example, if an Agent has 200 power tokens, and they've staked all 200 power tokens in pools, they can no longer borrow from any more pools until they either: (a) exit from a pool and receive their power token stake back, (b) add power to their Agent by staking another miner, or (c) proving to the agent that the FSP collateral base has more power than power tokens minted (and then minting more power tokens).

There is no set relationship between a power token stake and a borrowing amount or cost of capital - this is determined by the pools. However, in a liquidation event where a limited number of FIL becomes available to all the pools the Agent borrowed from, the liquidation proceeds are split pro-rata by the pools based on the % power token stake they received from the Agent. For instance, imagine an Agent that has 100 power tokens - 20 power tokens are staked in pool A and 80 power tokens in pool B. If the Agent gets liquidated for 100 FIL, pool A would receive 20 FIL and pool B would receive 80 FIL.

## Verifiable Credentials to access off-chain data

Since metrics like a Quality Adjusted Power, Liquidation Value, and Expected Daily Rewards are too computationally expensive to compute on-chain, Agents and Pools must rely on off-chain data to conduct business. For this reason, a Verifiable Credential Issuing service exists off-chain to transparently compute scores and report metrics about FSPs and Agents.

# Agent Police

The Agent Police is a mechanism for enforcing a number of Agent related policies across the entire system:

- An Agent may not borrow an amount with a pro-rated cost of capital greater than the expected daily rewards of the Agent. This is analogous to a traditional lender checking a potential borrower's W2 Income before issuing a loan - if the interest payments outweigh the monthly W2 income, there's a much higher risk of the borrower not being able to pay back the loan with interest.
- An Agent may not mint more power than they actually have on Filecoin.

With these policies in mind, an Agent can be in any one of 4 states:
- Active - the Agent is compliant with the above policies
- Overpowered - when the Agent has minted more power than they have
- Overleveraged - when the Agent has borrowed more than they can repay based on their expected daily rewards
- Default - when the Agent is both overpowered and overleveraged

Depending on what state the Agent is in, the police can take executive action:

1. When overpowered, the Agent Police can burn power tokens on behalf of the Agent
2. When overleveraged, the Agent Police can manually draw up funds from the Agent's collateralized FSPs, and make pro-rated payments to each of the pools
3. When in default, the Agent Police can completely liquidate the Agent's FSPs, recouping maximum possible funds

Note that actions 1 and 2 are _non-destructive_, meaning, neither of these actions should further _decrease_ any FSP QAP:
- The Agent Police cannot burn power tokens that are already staked in a pool
- The Agent Police cannot draw funds from the Agent's FSP that aren't readily available

However, action 3 is destructive, and should be avoided at all costs. In this scenario, the Agent Police can:
- Re-assign FSP's ownership structures so that a FSP's operators can no longer operate the FSP
- Terminate sectors early to avoid maximum penalty fees for a faulty sector

In our first iteration of the protocol, the Agent Police will have a preselected governing body that can take executive action. However, in a future iteration of the protocol, the Agent Police will be a decentralized task force with keeping Agents in check, and will economically reward policers that successfully police an Agent.
