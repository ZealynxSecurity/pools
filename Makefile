.PHONY: test

test:
	forge test -vvv

test-contract:
	forge test --match-contract $(CONTRACT_NAME) -vvv

test-watch:
	forge test -w -vvv

test-watch-contract:
	forge test --match-contract $(CONTRACT_NAME) -w -vvv
