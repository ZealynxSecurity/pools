import * as ethers from "ethers";
import { _TypedDataEncoder } from "ethers/lib/utils";

// represents https://www.w3.org/TR/xmlschema11-2/#dateTime
type DateTime = string;

type MinerData = {
  startEpoch: ethers.BigNumberish;
  power: ethers.BigNumberish;
  beta: ethers.BigNumberish;
};

type VerifiableCredential = {
  issuer: string;
  subject: string;
  epochIssued: ethers.BigNumberish;
  epochValidUntil: ethers.BigNumberish;
  miner: MinerData;
  // issued: DateTime;
  // validUntil: DateTime;
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
    name: "lending.glif.io",
    version: "1",
    // anvil
    chainId: 31337,
    verifyingContract: "0xCe71065D4017F316EC606Fe4422e11eB2c47c246",
  };

  const vcDataFields: ethers.TypedDataField[] = [
    { name: "issuer", type: "address" },
    { name: "subject", type: "address" },
    { name: "epochIssued", type: "uint256" },
    { name: "epochValidUntil", type: "uint256" },
    { name: "miner", type: "MinerData" },
  ];

  const minerDataFields: ethers.TypedDataField[] = [
    { name: "startEpoch", type: "uint256" },
    { name: "power", type: "uint256" },
    { name: "beta", type: "uint256" },
  ];

  const types: Record<string, ethers.TypedDataField[]> = {
    VerifiableCredential: vcDataFields,
    MinerData: minerDataFields,
  };

  const value: VerifiableCredential = {
    issuer: wallet.address,
    subject: wallet.address,
    epochIssued: "100",
    epochValidUntil: "100",
    miner: {
      startEpoch: "100",
      power: "100",
      beta: "100",
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
    // minerDataTypeHash,
    hashStruct,
  });
}

main();
