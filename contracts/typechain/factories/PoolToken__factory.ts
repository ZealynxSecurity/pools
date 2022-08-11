/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common";
import type { PoolToken, PoolTokenInterface } from "../PoolToken";

const _abi = [
  {
    inputs: [
      {
        internalType: "string",
        name: "_name",
        type: "string",
      },
      {
        internalType: "string",
        name: "_symbol",
        type: "string",
      },
      {
        internalType: "address",
        name: "_minter",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "spender",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "value",
        type: "uint256",
      },
    ],
    name: "Approval",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "from",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "to",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "value",
        type: "uint256",
      },
    ],
    name: "Transfer",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        internalType: "address",
        name: "spender",
        type: "address",
      },
    ],
    name: "allowance",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "spender",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "approve",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "account",
        type: "address",
      },
    ],
    name: "balanceOf",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "account",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "burn",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [
      {
        internalType: "uint8",
        name: "",
        type: "uint8",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "spender",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "subtractedValue",
        type: "uint256",
      },
    ],
    name: "decreaseAllowance",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "deployer",
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
        internalType: "address",
        name: "spender",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "addedValue",
        type: "uint256",
      },
    ],
    name: "increaseAllowance",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_address",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "mint",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "minter",
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
    name: "name",
    outputs: [
      {
        internalType: "string",
        name: "",
        type: "string",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "_minter",
        type: "address",
      },
    ],
    name: "setMinter",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "symbol",
    outputs: [
      {
        internalType: "string",
        name: "",
        type: "string",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "totalSupply",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "to",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "transfer",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "from",
        type: "address",
      },
      {
        internalType: "address",
        name: "to",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "transferFrom",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x60806040523480156200001157600080fd5b5060405162000ee238038062000ee2833981016040819052620000349162000155565b8282600362000044838262000271565b50600462000053828262000271565b5050600680546001600160a01b039093166001600160a01b0319938416179055506005805490911633179055506200033d9050565b634e487b7160e01b600052604160045260246000fd5b600082601f830112620000b057600080fd5b81516001600160401b0380821115620000cd57620000cd62000088565b604051601f8301601f19908116603f01168101908282118183101715620000f857620000f862000088565b816040528381526020925086838588010111156200011557600080fd5b600091505b838210156200013957858201830151818301840152908201906200011a565b838211156200014b5760008385830101525b9695505050505050565b6000806000606084860312156200016b57600080fd5b83516001600160401b03808211156200018357600080fd5b62000191878388016200009e565b94506020860151915080821115620001a857600080fd5b50620001b7868287016200009e565b604086015190935090506001600160a01b0381168114620001d757600080fd5b809150509250925092565b600181811c90821680620001f757607f821691505b6020821081036200021857634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200026c57600081815260208120601f850160051c81016020861015620002475750805b601f850160051c820191505b81811015620002685782815560010162000253565b5050505b505050565b81516001600160401b038111156200028d576200028d62000088565b620002a5816200029e8454620001e2565b846200021e565b602080601f831160018114620002dd5760008415620002c45750858301515b600019600386901b1c1916600185901b17855562000268565b600085815260208120601f198616915b828110156200030e57888601518255948401946001909101908401620002ed565b50858210156200032d5787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b610b95806200034d6000396000f3fe608060405234801561001057600080fd5b50600436106101005760003560e01c806370a0823111610097578063a9059cbb11610066578063a9059cbb14610224578063d5f3948814610237578063dd62ed3e1461024a578063fca3b5aa1461025d57600080fd5b806370a08231146101cd57806395d89b41146101f65780639dc29fac146101fe578063a457c2d71461021157600080fd5b806323b872dd116100d357806323b872dd14610183578063313ce5671461019657806339509351146101a557806340c10f19146101b857600080fd5b806306fdde03146101055780630754617214610123578063095ea7b31461014e57806318160ddd14610171575b600080fd5b61010d610270565b60405161011a91906109d3565b60405180910390f35b600654610136906001600160a01b031681565b6040516001600160a01b03909116815260200161011a565b61016161015c366004610a44565b610302565b604051901515815260200161011a565b6002545b60405190815260200161011a565b610161610191366004610a6e565b61031a565b6040516012815260200161011a565b6101616101b3366004610a44565b61033e565b6101cb6101c6366004610a44565b610360565b005b6101756101db366004610aaa565b6001600160a01b031660009081526020819052604090205490565b61010d610385565b6101cb61020c366004610a44565b610394565b61016161021f366004610a44565b6103b5565b610161610232366004610a44565b610435565b600554610136906001600160a01b031681565b610175610258366004610acc565b610443565b6101cb61026b366004610aaa565b61046e565b60606003805461027f90610aff565b80601f01602080910402602001604051908101604052809291908181526020018280546102ab90610aff565b80156102f85780601f106102cd576101008083540402835291602001916102f8565b820191906000526020600020905b8154815290600101906020018083116102db57829003601f168201915b5050505050905090565b6000336103108185856104a7565b5060019392505050565b6000336103288582856105cc565b610333858585610646565b506001949350505050565b6000336103108185856103518383610443565b61035b9190610b39565b6104a7565b6006546001600160a01b0316331461037757600080fd5b61038182826107ea565b5050565b60606004805461027f90610aff565b6006546001600160a01b031633146103ab57600080fd5b61038182826108a9565b600033816103c38286610443565b9050838110156104285760405162461bcd60e51b815260206004820152602560248201527f45524332303a2064656372656173656420616c6c6f77616e63652062656c6f77604482015264207a65726f60d81b60648201526084015b60405180910390fd5b61033382868684036104a7565b600033610310818585610646565b6001600160a01b03918216600090815260016020908152604080832093909416825291909152205490565b6005546001600160a01b0316331461048557600080fd5b600680546001600160a01b0319166001600160a01b0392909216919091179055565b6001600160a01b0383166105095760405162461bcd60e51b8152602060048201526024808201527f45524332303a20617070726f76652066726f6d20746865207a65726f206164646044820152637265737360e01b606482015260840161041f565b6001600160a01b03821661056a5760405162461bcd60e51b815260206004820152602260248201527f45524332303a20617070726f766520746f20746865207a65726f206164647265604482015261737360f01b606482015260840161041f565b6001600160a01b0383811660008181526001602090815260408083209487168084529482529182902085905590518481527f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b92591015b60405180910390a3505050565b60006105d88484610443565b9050600019811461064057818110156106335760405162461bcd60e51b815260206004820152601d60248201527f45524332303a20696e73756666696369656e7420616c6c6f77616e6365000000604482015260640161041f565b61064084848484036104a7565b50505050565b6001600160a01b0383166106aa5760405162461bcd60e51b815260206004820152602560248201527f45524332303a207472616e736665722066726f6d20746865207a65726f206164604482015264647265737360d81b606482015260840161041f565b6001600160a01b03821661070c5760405162461bcd60e51b815260206004820152602360248201527f45524332303a207472616e7366657220746f20746865207a65726f206164647260448201526265737360e81b606482015260840161041f565b6001600160a01b038316600090815260208190526040902054818110156107845760405162461bcd60e51b815260206004820152602660248201527f45524332303a207472616e7366657220616d6f756e7420657863656564732062604482015265616c616e636560d01b606482015260840161041f565b6001600160a01b03848116600081815260208181526040808320878703905593871680835291849020805487019055925185815290927fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a3610640565b6001600160a01b0382166108405760405162461bcd60e51b815260206004820152601f60248201527f45524332303a206d696e7420746f20746865207a65726f206164647265737300604482015260640161041f565b80600260008282546108529190610b39565b90915550506001600160a01b038216600081815260208181526040808320805486019055518481527fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef910160405180910390a35050565b6001600160a01b0382166109095760405162461bcd60e51b815260206004820152602160248201527f45524332303a206275726e2066726f6d20746865207a65726f206164647265736044820152607360f81b606482015260840161041f565b6001600160a01b0382166000908152602081905260409020548181101561097d5760405162461bcd60e51b815260206004820152602260248201527f45524332303a206275726e20616d6f756e7420657863656564732062616c616e604482015261636560f01b606482015260840161041f565b6001600160a01b0383166000818152602081815260408083208686039055600280548790039055518581529192917fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef91016105bf565b600060208083528351808285015260005b81811015610a00578581018301518582016040015282016109e4565b81811115610a12576000604083870101525b50601f01601f1916929092016040019392505050565b80356001600160a01b0381168114610a3f57600080fd5b919050565b60008060408385031215610a5757600080fd5b610a6083610a28565b946020939093013593505050565b600080600060608486031215610a8357600080fd5b610a8c84610a28565b9250610a9a60208501610a28565b9150604084013590509250925092565b600060208284031215610abc57600080fd5b610ac582610a28565b9392505050565b60008060408385031215610adf57600080fd5b610ae883610a28565b9150610af660208401610a28565b90509250929050565b600181811c90821680610b1357607f821691505b602082108103610b3357634e487b7160e01b600052602260045260246000fd5b50919050565b60008219821115610b5a57634e487b7160e01b600052601160045260246000fd5b50019056fea26469706673582212204f6b914fcc30df73a4d5c99f779b7b1b8295e022cfd93653d1b76dc5ddd77df864736f6c634300080f0033";

type PoolTokenConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: PoolTokenConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class PoolToken__factory extends ContractFactory {
  constructor(...args: PoolTokenConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _name: PromiseOrValue<string>,
    _symbol: PromiseOrValue<string>,
    _minter: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<PoolToken> {
    return super.deploy(
      _name,
      _symbol,
      _minter,
      overrides || {}
    ) as Promise<PoolToken>;
  }
  override getDeployTransaction(
    _name: PromiseOrValue<string>,
    _symbol: PromiseOrValue<string>,
    _minter: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(_name, _symbol, _minter, overrides || {});
  }
  override attach(address: string): PoolToken {
    return super.attach(address) as PoolToken;
  }
  override connect(signer: Signer): PoolToken__factory {
    return super.connect(signer) as PoolToken__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): PoolTokenInterface {
    return new utils.Interface(_abi) as PoolTokenInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): PoolToken {
    return new Contract(address, _abi, signerOrProvider) as PoolToken;
  }
}
