/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common";
import type { LoanAgent, LoanAgentInterface } from "../LoanAgent";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_miner",
        type: "address",
      },
      {
        internalType: "address",
        name: "_poolFactory",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [],
    name: "active",
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
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "poolID",
        type: "uint256",
      },
    ],
    name: "borrow",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "claimOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "isDebtor",
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
    name: "miner",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "owner",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "poolFactory",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "poolID",
        type: "uint256",
      },
    ],
    name: "repay",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "newOwner",
        type: "address",
      },
    ],
    name: "revokeMinerOwnership",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "withdrawBalance",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    stateMutability: "payable",
    type: "receive",
  },
];

const _bytecode =
  "0x60806040526002805460ff60a01b1916905534801561001d57600080fd5b50604051610f40380380610f4083398101604081905261003c91610089565b600080546001600160a01b039384166001600160a01b031991821617909155600280549290931691161790556100bc565b80516001600160a01b038116811461008457600080fd5b919050565b6000806040838503121561009c57600080fd5b6100a58361006d565b91506100b36020840161006d565b90509250929050565b610e75806100cb6000396000f3fe6080604052600436106100945760003560e01c8063480727441161005957806348072744146101655780634e71e0c8146101855780635fd8c7101461019a5780638da5cb5b146101bd578063d8aed145146101dd57600080fd5b8062b7f20a146100a057806302fb0c5e146100ca5780630ecbcdab146100eb578063349dc3291461010d5780634219dc401461014557600080fd5b3661009b57005b600080fd5b3480156100ac57600080fd5b506100b56101fd565b60405190151581526020015b60405180910390f35b3480156100d657600080fd5b506002546100b590600160a01b900460ff1681565b3480156100f757600080fd5b5061010b610106366004610d69565b61037d565b005b34801561011957600080fd5b5060005461012d906001600160a01b031681565b6040516001600160a01b0390911681526020016100c1565b34801561015157600080fd5b5060025461012d906001600160a01b031681565b34801561017157600080fd5b5061010b610180366004610da3565b610469565b34801561019157600080fd5b5061010b61067d565b3480156101a657600080fd5b506101af610801565b6040519081526020016100c1565b3480156101c957600080fd5b5060015461012d906001600160a01b031681565b3480156101e957600080fd5b5061010b6101f8366004610d69565b610876565b6000805b600260009054906101000a90046001600160a01b03166001600160a01b031663efde4e646040518163ffffffff1660e01b8152600401602060405180830381865afa158015610254573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102789190610dc0565b811015610375576002546040516341d1de9760e01b8152600481018390526000916001600160a01b0316906341d1de9790602401602060405180830381865afa1580156102c9573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906102ed9190610dd9565b604051639aae66f960e01b81523060048201526001600160a01b039190911690639aae66f990602401602060405180830381865afa158015610333573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906103579190610dc0565b111561036557600191505090565b61036e81610df6565b9050610201565b506000905090565b6001546001600160a01b031633146103e85760405162461bcd60e51b8152602060048201526024808201527f4f6e6c79204c6f616e4167656e74206f776e65722063616e2063616c6c20626f60448201526372726f7760e01b60648201526084015b60405180910390fd5b6103f181610c45565b604051630967fa2960e31b8152600481018490523060248201526001600160a01b039190911690634b3fd148906044016020604051808303816000875af1158015610440573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906104649190610dc0565b505050565b6001546001600160a01b031633146104d95760405162461bcd60e51b815260206004820152602d60248201527f4f6e6c79204c6f616e4167656e74206f776e65722063616e2063616c6c20726560448201526c0766f6b654f776e65727368697609c1b60648201526084016103df565b600054604080516359c3f7c960e11b8152905130926001600160a01b03169163b387ef929160048083019260209291908290030181865afa158015610522573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906105469190610dd9565b6001600160a01b03161461059c5760405162461bcd60e51b815260206004820152601c60248201527f4c6f616e4167656e7420646f6573206e6f74206f776e206d696e65720000000060448201526064016103df565b6105a46101fd565b1561060e5760405162461bcd60e51b815260206004820152603460248201527f43616e6e6f74207265766f6b65206d696e6572206f776e6572736869702077696044820152737468206f75747374616e64696e67206c6f616e7360601b60648201526084016103df565b6000546040516385eac05f60e01b81526001600160a01b038381166004830152909116906385eac05f90602401600060405180830381600087803b15801561065557600080fd5b505af1158015610669573d6000803e3d6000fd5b50506002805460ff60a01b19169055505050565b600054604080516369f3331d60e01b8152905130926001600160a01b0316916369f3331d9160048083019260209291908290030181865afa1580156106c6573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906106ea9190610dd9565b6001600160a01b0316146106fd57600080fd5b600054604080516359c3f7c960e11b8152905133926001600160a01b03169163b387ef929160048083019260209291908290030181865afa158015610746573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019061076a9190610dd9565b6001600160a01b03161461077d57600080fd5b6000546040516385eac05f60e01b81523060048201526001600160a01b03909116906385eac05f90602401600060405180830381600087803b1580156107c257600080fd5b505af11580156107d6573d6000803e3d6000fd5b5050600180546001600160a01b0319163317905550506002805460ff60a01b1916600160a01b179055565b6000805460405163da76d5cd60e01b8152600481018390526001600160a01b039091169063da76d5cd906024016020604051808303816000875af115801561084d573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906108719190610dc0565b905090565b6001546001600160a01b031633146108dc5760405162461bcd60e51b815260206004820152602360248201527f4f6e6c79204c6f616e4167656e74206f776e65722063616e2063616c6c20726560448201526270617960e81b60648201526084016103df565b816108e682610c45565b6001600160a01b03166338d52e0f6040518163ffffffff1660e01b8152600401602060405180830381865afa158015610923573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906109479190610dd9565b6040516370a0823160e01b81523060048201526001600160a01b0391909116906370a0823190602401602060405180830381865afa15801561098d573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906109b19190610dc0565b101580156109bd575060015b610a155760405162461bcd60e51b8152602060048201526024808201527f496e76616c696420616d6f756e742070617373656420746f20706179646f776e6044820152631119589d60e21b60648201526084016103df565b81600003610af457610a2681610c45565b6001600160a01b03166338d52e0f6040518163ffffffff1660e01b8152600401602060405180830381865afa158015610a63573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610a879190610dd9565b6040516370a0823160e01b81523060048201526001600160a01b0391909116906370a0823190602401602060405180830381865afa158015610acd573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610af19190610dc0565b91505b6000610aff82610c45565b9050806001600160a01b03166338d52e0f6040518163ffffffff1660e01b8152600401602060405180830381865afa158015610b3f573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610b639190610dd9565b60405163095ea7b360e01b81526001600160a01b03838116600483015260248201869052919091169063095ea7b3906044016020604051808303816000875af1158015610bb4573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610bd89190610e1d565b5060405163c883b2e560e01b815260048101849052306024820181905260448201526001600160a01b0382169063c883b2e590606401600060405180830381600087803b158015610c2857600080fd5b505af1158015610c3c573d6000803e3d6000fd5b50505050505050565b60025460408051633bf7939960e21b815290516000926001600160a01b03169163efde4e649160048083019260209291908290030181865afa158015610c8f573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610cb39190610dc0565b821115610cf45760405162461bcd60e51b815260206004820152600f60248201526e125b9d985b1a59081c1bdbdb081251608a1b60448201526064016103df565b6002546040516341d1de9760e01b8152600481018490526000916001600160a01b0316906341d1de9790602401602060405180830381865afa158015610d3e573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610d629190610dd9565b9392505050565b60008060408385031215610d7c57600080fd5b50508035926020909101359150565b6001600160a01b0381168114610da057600080fd5b50565b600060208284031215610db557600080fd5b8135610d6281610d8b565b600060208284031215610dd257600080fd5b5051919050565b600060208284031215610deb57600080fd5b8151610d6281610d8b565b600060018201610e1657634e487b7160e01b600052601160045260246000fd5b5060010190565b600060208284031215610e2f57600080fd5b81518015158114610d6257600080fdfea26469706673582212202e8fad186c62dd74643c5cae018f1d81d2833de86156743b6043fc00208361d464736f6c634300080f0033";

type LoanAgentConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: LoanAgentConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class LoanAgent__factory extends ContractFactory {
  constructor(...args: LoanAgentConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _miner: PromiseOrValue<string>,
    _poolFactory: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<LoanAgent> {
    return super.deploy(
      _miner,
      _poolFactory,
      overrides || {}
    ) as Promise<LoanAgent>;
  }
  override getDeployTransaction(
    _miner: PromiseOrValue<string>,
    _poolFactory: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(_miner, _poolFactory, overrides || {});
  }
  override attach(address: string): LoanAgent {
    return super.attach(address) as LoanAgent;
  }
  override connect(signer: Signer): LoanAgent__factory {
    return super.connect(signer) as LoanAgent__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): LoanAgentInterface {
    return new utils.Interface(_abi) as LoanAgentInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): LoanAgent {
    return new Contract(address, _abi, signerOrProvider) as LoanAgent;
  }
}
