import fs from "fs";
import path from "path";

type AdditionalContract = {
  transactionType: string;
  address: string;
  initCode: string;
};

type Transaction = {
  hash: string;
  transactionType: string;
  contractName: string;
  contractAddress: string;
  function: string | null;
  arguments: any;
  transaction: {
    type: string;
    from: string;
    gas: string;
    value: string;
    data: string;
    nonce: string;
    accessList: any[];
  };
  additionalContracts: AdditionalContract[];
};

type Receipt = {
  transactionHash: string;
  transactionIndex: string;
  blockHash: string;
  blockNumber: string;
  from: string;
  to: any;
  cumulativeGasUsed: string;
  gasUsed: string;
  contractAddress: string;
  logs: [];
  status: string;
  logsBloom: string;
  effectiveGasPrice: string;
};

type LatestRun = {
  transactions: Transaction[];
  receipts: Receipt[];
  libraries: any[];
  pending: any[];
  path: string;
  returns: object;
  timestamp: number;
  commit: string;
};

type CompiledContract = {
  abi: object[];
  bytecode: object;
  deployedBytecode: object;
  methodIdentifier: object;
  ast: object;
  id: number;
};

type ContractInfo = {
  name: string;
  address: string;
  abi: any[];
};

type Digest = Record<string, ContractInfo | ContractInfo[]>;

/**
 * This script does the following:
 * - Gathers all the contract addresses deployed to the network
 * - Merges the contract addresses with their ABIs
 * - Writes a JSON file with the contract info to ./generated
 */
async function main() {
  const pathToDemoBroadcast = `${__dirname}/../broadcast/Demo.s.sol`;
  const [demoRun] = fs.readdirSync(path.resolve(pathToDemoBroadcast));
  const pathToLatestRun = `${pathToDemoBroadcast}/${demoRun}/run-latest.json`;
  const json = JSON.parse(
    fs.readFileSync(pathToLatestRun, "utf8")
  ) as LatestRun;

  // filter for CREATE transactions with null function (contract instantiation)
  const createTxs = json.transactions.filter(
    ({ transactionType, function: fn }) => transactionType === "CREATE" && !fn
  );

  // add in calls to the `create` method on the AgentFactory
  const createLATxs = json.transactions
    .filter(({ transactionType, contractName, function: invoked }) => {
      return (
        transactionType === "CREATE" &&
        contractName === "AgentFactory" &&
        invoked?.includes("create(")
      );
    })
    .map(({ additionalContracts }) => ({
      contractName: "Agent",
      contractAddress: additionalContracts[0].address,
    }));

  // add in calls to the `create` method on the PoolRegistry
  const createPoolTxs = json.transactions
    .filter(({ transactionType, contractName, function: invoked }) => {
      return (
        transactionType === "CREATE" &&
        contractName === "PoolRegistry" &&
        invoked?.includes("createSimpleInterestPool(")
      );
    })
    .map(({ additionalContracts }) => ({
      contractName: "SimpleInterestPool",
      contractAddress: additionalContracts[0].address,
    }));

  // add in ABIs
  const contractsInfo: ContractInfo[] = [
    ...createTxs,
    ...createLATxs,
    ...createPoolTxs,
  ].map((tx) => {
    const pathToCompiledContract = `${__dirname}/../out/${tx.contractName}.sol/${tx.contractName}.json`;
    const file = JSON.parse(
      fs.readFileSync(pathToCompiledContract, "utf8")
    ) as CompiledContract;

    return {
      name: tx.contractName,
      address: tx.contractAddress,
      abi: file.abi,
    };
  });

  const res = contractsInfo.reduce((accum, ele) => {
    switch (ele.name) {
      case "MockMiner":
      case "Agent":
      case "SimpleInterestPool": {
        if (!!accum?.[ele.name]) {
          (accum[ele.name] as ContractInfo[]).push(ele);
        } else {
          accum[ele.name] = [ele];
        }
        break;
      }
      default:
        accum[ele.name] = ele;
    }
    return accum;
  }, {} as Digest);

  const WRITE_PATH = `${__dirname}/../generated/contractDigest.json`;
  fs.writeFileSync(WRITE_PATH, Buffer.from(JSON.stringify(res), "utf8"));

  console.log("Success, contract digest written to: ", WRITE_PATH);
}

main();
