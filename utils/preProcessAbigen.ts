import fs from "fs";
import path from "path";

/**
 * This utility creates `.bin` and `.abi` files for the smart contracts below
 * We use these generated files with go-ethereum's abigen tool to create go bindings for our smart contracts
 * You run the command like:
 * `abigen --bin=VCVerifier.bin --abi=VCVerifier.abi --pkg=chain --out=VCVerifier.go`
 */
const CONTRACTS_TO_PROCESS = [
  "VCVerifier",
  "Router",
  "LoanAgentFactory",
  "LoanAgent",
  "ERC20",
  "ERC4626",
  "Stats",
];

type Bytecode = {
  object: string;
};

interface CompiledContract {
  abi: Object[];
  bytecode: Bytecode;
}

async function main() {
  for (let i = 0; i < CONTRACTS_TO_PROCESS.length; i++) {
    const c = CONTRACTS_TO_PROCESS[i];
    const filePath = path.resolve(`${__dirname}/../out/${c}.sol/${c}.json`);
    const json = JSON.parse(
      fs.readFileSync(filePath, "utf8")
    ) as CompiledContract;
    const abi = JSON.stringify(json.abi);
    // chop off 0x from the hex bytecode
    const bytecode = json.bytecode.object.slice(2);

    const ABI_WRITE_PATH = `${__dirname}/../generated/${c}.abi`;
    fs.writeFileSync(ABI_WRITE_PATH, Buffer.from(abi));
    const BYTECODE_WRITE_PATH = `${__dirname}/../generated/${c}.bin`;
    fs.writeFileSync(BYTECODE_WRITE_PATH, Buffer.from(bytecode));
  }
}

main();
