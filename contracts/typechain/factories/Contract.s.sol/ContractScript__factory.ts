/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../../common";
import type {
  ContractScript,
  ContractScriptInterface,
} from "../../Contract.s.sol/ContractScript";

const _abi = [
  {
    inputs: [],
    name: "IS_SCRIPT",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "run",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "setUp",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "vm",
    outputs: [
      {
        internalType: "contract Vm",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x60806040526000805460ff1916600117905534801561001d57600080fd5b5061014c8061002d6000396000f3fe608060405234801561001057600080fd5b506004361061004c5760003560e01c80630a9254e4146100515780633a76846314610053578063c04062261461008b578063f8ccbf4714610093575b600080fd5b005b61006e737109709ecfa91a80626ff3989d68f67f5b1dd12d81565b6040516001600160a01b0390911681526020015b60405180910390f35b6100516100b0565b6000546100a09060ff1681565b6040519015158152602001610082565b604080516302bf260160e61b81529051737109709ecfa91a80626ff3989d68f67f5b1dd12d9163afc9804091600480830192600092919082900301818387803b1580156100fc57600080fd5b505af1158015610110573d6000803e3d6000fd5b5050505056fea26469706673582212205b9097bd26b8f84405df228f811d07c9123d66718e2027eb4a503ef57964861564736f6c634300080f0033";

type ContractScriptConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: ContractScriptConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class ContractScript__factory extends ContractFactory {
  constructor(...args: ContractScriptConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractScript> {
    return super.deploy(overrides || {}) as Promise<ContractScript>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): ContractScript {
    return super.attach(address) as ContractScript;
  }
  override connect(signer: Signer): ContractScript__factory {
    return super.connect(signer) as ContractScript__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): ContractScriptInterface {
    return new utils.Interface(_abi) as ContractScriptInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): ContractScript {
    return new Contract(address, _abi, signerOrProvider) as ContractScript;
  }
}
