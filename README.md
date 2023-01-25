# WELCOME TO GLIF POOLS

Alleviating Filecoin's capital inefficiences through a novel staking and lending protocol.

This is the GLIF Pools smart contracts

## Getting started

Make sure you have installed:

[Foundry](https://docs.google.com/document/d/1gaX5ailGE1pAewANUtmjsQTiykH03T2nMbrp4rwamYI/edit?pli=1)<br />
[Yarn](https://yarnpkg.com/)

Make sure the `.env.local` is set up with all variables exported.

## Running tests

For testing contracts, from the repository root, run `yarn test:contracts`. Under the hood, this runs the forge testing suite, so you can pass any flag as you would directly to forge. For example, to run the SimpleInterestPool tests in watch mode, with logging enabled, you would run: `yarn test:contracts -w -vvv --match-contract SimpleInterestPool`

## Artifacts action

On GitHub, you can run the `artifacts` action to generate typechain types as well as build artifacts like the `.bin` and `.abi` files for specific contracts


