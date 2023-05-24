
OUTPUT_FEVM=solc-output/fevm
OUTPUT_MOCK=solc-output/mock

SRC=\
  src/Agent/AgentFactory.sol \
	src/Router/Router.sol \
  src/Credentials/CredParser.sol \
  src/Pool/InfinityPool.sol \
  src/Pool/RateModule.sol \
  src/Pool/PoolRegistry.sol \
  src/Types/Interfaces/IERC4626.sol \
  src/Agent/AgentPolice.sol \
  src/Agent/MinerRegistry.sol \
  test/helpers/MockMiner.sol

SRC_MOCK=\
	shim/Mock/WFIL.sol

SHIMMED_SRC=\
	src/Ping.sol \
	src/Agent/Agent.sol \
  src/Agent/AgentDeployer.sol


all: mock fevm sizes

mock:
	@mkdir -p $(OUTPUT_MOCK)
	@echo ">>> Compiling mock contracts"
	solc \
		--overwrite \
		-o $(OUTPUT_MOCK) \
		--bin --abi --hashes \
		--optimize --optimize-runs 1000000 \
		"@ensdomains/buffer/=lib/buffer/" \
		"@openzeppelin/=lib/openzeppelin-contracts/" \
		"@zondax/solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/" \
		"buffer/=lib/buffer/contracts/" \
		"bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"deploy/=deploy/" \
		"ds-test/=lib/forge-std/lib/ds-test/src/" \
		"fevmate/=lib/fevmate/contracts/" \
		"filecoin-solidity/=lib/filecoin-solidity/contracts/v0.8/" \
		"forge-std/=lib/forge-std/src/" \
		"glifmate/=lib/glifmate/src/" \
		"openzeppelin-contracts/=lib/openzeppelin-contracts/" \
		"shim/=shim/Mock/" \
		"solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/src/" \
		"solidity-bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"solidity-cborutils/=lib/solidity-cborutils/" \
		"solidity-cborutils/contracts/=lib/filecoin-solidity/lib/solidity-cborutils/contracts/" \
		"solmate/=lib/solmate/src/" \
		"src/=src/" \
		$(SRC) $(SRC_MOCK) $(SHIMMED_SRC)

fevm:
	@mkdir -p $(OUTPUT_FEVM)
	@echo ">>> Compiling regular contracts"
	solc \
		--overwrite \
		-o $(OUTPUT_FEVM) \
		--bin --abi --hashes \
		--optimize --optimize-runs 1000000 \
		"@ensdomains/buffer/=lib/buffer/" \
		"@openzeppelin/=lib/openzeppelin-contracts/" \
		"@zondax/solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/" \
		"buffer/=lib/buffer/contracts/" \
		"bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"deploy/=deploy/" \
		"ds-test/=lib/forge-std/lib/ds-test/src/" \
		"fevmate/=lib/fevmate/contracts/" \
		"filecoin-solidity/=lib/filecoin-solidity/contracts/v0.8/" \
		"forge-std/=lib/forge-std/src/" \
		"glifmate/=lib/glifmate/src/" \
		"openzeppelin-contracts/=lib/openzeppelin-contracts/" \
		"shim/=shim/FEVM/" \
		"solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/src/" \
		"solidity-bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"solidity-cborutils/=lib/solidity-cborutils/" \
		"solidity-cborutils/contracts/=lib/filecoin-solidity/lib/solidity-cborutils/contracts/" \
		"solmate/=lib/solmate/src/" \
		"src/=src/" \
		$(SRC)
	@echo ">>> Compiling contracts that use Filecoin.sol"
	solc \
		--overwrite \
		-o $(OUTPUT_FEVM) \
		--bin --abi --hashes \
		--optimize --optimize-runs 5000 --no-optimize-yul \
		"@ensdomains/buffer/=lib/buffer/" \
		"@openzeppelin/=lib/openzeppelin-contracts/" \
		"@zondax/solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/" \
		"buffer/=lib/buffer/contracts/" \
		"bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"deploy/=deploy/" \
		"ds-test/=lib/forge-std/lib/ds-test/src/" \
		"fevmate/=lib/fevmate/contracts/" \
		"filecoin-solidity/=lib/filecoin-solidity/contracts/v0.8/" \
		"forge-std/=lib/forge-std/src/" \
		"glifmate/=lib/glifmate/src/" \
		"openzeppelin-contracts/=lib/openzeppelin-contracts/" \
		"shim/=shim/FEVM/" \
		"solidity-bignumber/=lib/filecoin-solidity/lib/solidity-bignumber/src/" \
		"solidity-bytes-utils/=lib/solidity-bytes-utils/contracts/" \
		"solidity-cborutils/=lib/solidity-cborutils/" \
		"solidity-cborutils/contracts/=lib/filecoin-solidity/lib/solidity-cborutils/contracts/" \
		"solmate/=lib/solmate/src/" \
		"src/=src/" \
		$(SHIMMED_SRC)

sizes:
	@echo ">>> Largest contract sizes (Max: 24576)"
	@for f in `find solc-output -name '*.bin'`; do \
		echo $$f $$(($$(cat $$f | wc -c) / 2)); \
	 done | sort -nk2 | tail -10

clean:
	rm -rf solc-output
