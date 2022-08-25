# WELCOME TO G-CRED

Alleviating Filecoin's capital inefficiences through a novel staking and lending protocol.

This is the G-CRED monorepo containing our smart contracts, tooling, and demo apps.

## Getting started

Make sure you have installed:

[Foundry](https://docs.google.com/document/d/1gaX5ailGE1pAewANUtmjsQTiykH03T2nMbrp4rwamYI/edit?pli=1)<br />
[Yarn](https://yarnpkg.com/)

## Running tests

## Running the demo app

`yarn demo`

Under the hood this:<br />
_Deploy:_

- Compiles all of our smart contracts
- Spins up an Anvil local EVM client
- Deploys the smart contracts to the Anvil client
- Caches the deployed contract addresses

_Interact:_

- Generates typescript types from the smart contracts
- Copies types, abis, and deployed addresses into the apps/demo workspace
- Spins up the demo app on port `:1010`
