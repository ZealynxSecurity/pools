# WELCOME TO GLIF POOLS

Alleviating Filecoin's capital inefficiences through a novel Filecoin leasing protocol.

This is the GLIF Pools smart contracts repo.

## Getting started

Make sure you have installed:

[Foundry](https://docs.google.com/document/d/1gaX5ailGE1pAewANUtmjsQTiykH03T2nMbrp4rwamYI/edit?pli=1)<br />
[Yarn](https://yarnpkg.com/)

## Running tests

`forge test`

## Remappings

This repo uses solidity remappings to mock the `/shim` directory in forge environments. The production deploy uses `/shim/FEVM`, and FEVM integration tests are run from a separate repository, which will be made public soon.

## Artifacts action

On GitHub, you can run the `artifacts` action to generate typechain types as well as build artifacts like the `.bin` and `.abi` files for specific contracts
