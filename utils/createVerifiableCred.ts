import * as ethers from "ethers";
import { _TypedDataEncoder } from "ethers/lib/utils";

type AgentData = {
  assets: ethers.BigNumberish;
  expectedDailyRewards: ethers.BigNumberish;
  exposureAtDefault: ethers.BigNumberish;
  expectedLoss: ethers.BigNumberish;
  liabilities: ethers.BigNumberish;
  liquidationValue: ethers.BigNumberish;
  lossGivenDefault: ethers.BigNumberish;
  probabilityOfDefault: ethers.BigNumberish;
  qaPower: ethers.BigNumberish;
  rawPower: ethers.BigNumberish;
  startEpoch: ethers.BigNumberish;
  unexpectedLoss: ethers.BigNumberish;
};

type VerifiableCredential = {
  issuer: string;
  subject: string;
  epochIssued: ethers.BigNumberish;
  epochValidUntil: ethers.BigNumberish;
  agent: AgentData;
};

function encodeType(
  name: string,
  fields: Array<ethers.TypedDataField>
): string {
  return `${name}(${fields
    .map(({ name, type }) => type + " " + name)
    .join(",")})`;
}

async function main() {
  const provider = new ethers.providers.JsonRpcProvider();
  const wallet = ethers.Wallet.fromMnemonic(
    "test test test test test test test test test test test junk"
  ).connect(provider);

  const domain: ethers.TypedDataDomain = {
    name: "glif.io",
    version: "1",
    // anvil
    chainId: 31337,
    verifyingContract: "0xce71065d4017f316ec606fe4422e11eb2c47c246",
  };

  const vcDataFields: ethers.TypedDataField[] = [
    { name: "issuer", type: "address" },
    { name: "subject", type: "address" },
    { name: "epochIssued", type: "uint256" },
    { name: "epochValidUntil", type: "uint256" },
    { name: "miner", type: "AgentData" },
  ];

  const agentDataFields: ethers.TypedDataField[] = [
    { name: "assets", type: "uint256" },
    { name: "expectedDailyRewards", type: "uint256" },
    { name: "exposureAtDefault", type: "uint256" },
    { name: "expectedLoss", type: "uint256" },
    { name: "liabilities", type: "uint256" },
    { name: "liquidationValue", type: "uint256" },
    { name: "lossGivenDefault", type: "uint256" },
    { name: "probabilityOfDefault", type: "uint256" },
    { name: "qaPower", type: "uint256" },
    { name: "rawPower", type: "uint256" },
    { name: "startEpoch", type: "uint256" },
    { name: "unexpectedLoss", type: "uint256" },
  ];

  const types: Record<string, ethers.TypedDataField[]> = {
    VerifiableCredential: vcDataFields,
    AgentData: agentDataFields,
  };

  const value: VerifiableCredential = {
    issuer: wallet.address,
    subject: wallet.address,
    epochIssued: "100",
    epochValidUntil: "100",
    agent: {
      assets: "100",
      expectedDailyRewards: "100",
      exposureAtDefault: "100",
      expectedLoss: "100",
      liabilities: "100",
      liquidationValue: "100",
      lossGivenDefault: "100",
      probabilityOfDefault: "100",
      qaPower: "100",
      rawPower: "100",
      startEpoch: "100",
      unexpectedLoss: "100",
    },
  };

  const eip712Hash = _TypedDataEncoder.hash(domain, types, value);
  const payload = _TypedDataEncoder.getPayload(domain, types, value);
  const domainHashDataHex = _TypedDataEncoder.hashDomain(domain);
  const primaryType = _TypedDataEncoder.getPrimaryType(types);
  const vcTypeHash = ethers.utils.id(
    encodeType("VerifiableCredential", vcDataFields)
  );
  const hashStruct = _TypedDataEncoder.hashStruct(
    "VerifiableCredential",
    types,
    value
  );
  const signature = await wallet._signTypedData(domain, types, value);
  const { r, s, v } = ethers.utils.splitSignature(signature);
  console.log({
    address: wallet.address,
    eip712Hash,
    payload,
    domainHashDataHex,
    signature,
    r,
    s,
    v,
    primaryType,
    vcTypeHash,
    hashStruct,
  });
}

main();
