# WELCOME TO G-CRED

Alleviating Filecoin's capital inefficiences through a novel staking and lending protocol.

This is the G-CRED monorepo containing our smart contracts, tooling, and demo apps.

## Getting started

Make sure you have installed:

[Foundry](https://docs.google.com/document/d/1gaX5ailGE1pAewANUtmjsQTiykH03T2nMbrp4rwamYI/edit?pli=1)<br />
[Yarn](https://yarnpkg.com/)

## Running tests

## Running the demo app

The demo app can technically be run on any blockchain node, but we generally expect a local Ethereum node to be running on portfolio 8545. We use [anvil](https://github.com/foundry-rs/foundry/tree/master/anvil).

1. Make sure the `.env.local` is set up with all variables exported.
2. To start the node, run `yarn start:node`
3. In a separate terminal window, run `yarn demo`

Under the hood this:<br />
_Deploy:_

- Compiles all of our smart contracts
- Deploys the smart contracts to the Anvil client
- Caches the deployed contract addresses

_Interact:_

- Generates typescript types from the smart contracts
- Copies types, abis, and deployed addresses into the apps/demo workspace
- Spins up the demo app on port `:1010`
