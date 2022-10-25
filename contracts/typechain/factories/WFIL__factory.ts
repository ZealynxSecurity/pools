/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common";
import type { WFIL, WFILInterface } from "../WFIL";

const _abi = [
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
        name: "amount",
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
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "Deposit",
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
        name: "amount",
        type: "uint256",
      },
    ],
    name: "Transfer",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "to",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "Withdrawal",
    type: "event",
  },
  {
    inputs: [],
    name: "DOMAIN_SEPARATOR",
    outputs: [
      {
        internalType: "bytes32",
        name: "",
        type: "bytes32",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
      {
        internalType: "address",
        name: "",
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
        name: "",
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
    inputs: [],
    name: "deposit",
    outputs: [],
    stateMutability: "payable",
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
        name: "",
        type: "address",
      },
    ],
    name: "nonces",
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
        name: "owner",
        type: "address",
      },
      {
        internalType: "address",
        name: "spender",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "value",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "deadline",
        type: "uint256",
      },
      {
        internalType: "uint8",
        name: "v",
        type: "uint8",
      },
      {
        internalType: "bytes32",
        name: "r",
        type: "bytes32",
      },
      {
        internalType: "bytes32",
        name: "s",
        type: "bytes32",
      },
    ],
    name: "permit",
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
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "withdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    stateMutability: "payable",
    type: "receive",
  },
];

const _bytecode =
  "0x60e06040523480156200001157600080fd5b506040518060400160405280601081526020016f2bb930b83832b2102334b632b1b7b4b760811b8152506040518060400160405280600481526020016315d1925360e21b815250601282600090816200006b9190620001de565b5060016200007a8382620001de565b5060ff81166080524660a052620000906200009d565b60c0525062000328915050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f6000604051620000d19190620002aa565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b634e487b7160e01b600052604160045260246000fd5b600181811c908216806200016457607f821691505b6020821081036200018557634e487b7160e01b600052602260045260246000fd5b50919050565b601f821115620001d957600081815260208120601f850160051c81016020861015620001b45750805b601f850160051c820191505b81811015620001d557828155600101620001c0565b5050505b505050565b81516001600160401b03811115620001fa57620001fa62000139565b62000212816200020b84546200014f565b846200018b565b602080601f8311600181146200024a5760008415620002315750858301515b600019600386901b1c1916600185901b178555620001d5565b600085815260208120601f198616915b828110156200027b578886015182559484019460019091019084016200025a565b50858210156200029a5787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b6000808354620002ba816200014f565b60018281168015620002d55760018114620002eb576200031c565b60ff19841687528215158302870194506200031c565b8760005260208060002060005b85811015620003135781548a820152908401908201620002f8565b50505082870194505b50929695505050505050565b60805160a05160c051610d5462000358600039600061059e01526000610569015260006101c60152610d546000f3fe6080604052600436106100e15760003560e01c806370a082311161007f578063a9059cbb11610059578063a9059cbb1461027e578063d0e30db01461029e578063d505accf146102a6578063dd62ed3e146102c657600080fd5b806370a082311461020f5780637ecebe001461023c57806395d89b411461026957600080fd5b806323b872dd116100bb57806323b872dd146101745780632e1a7d4d14610194578063313ce567146101b45780633644e515146101fa57600080fd5b806306fdde03146100f5578063095ea7b31461012057806318160ddd1461015057600080fd5b366100f0576100ee6102fe565b005b600080fd5b34801561010157600080fd5b5061010a61033f565b6040516101179190610a28565b60405180910390f35b34801561012c57600080fd5b5061014061013b366004610a99565b6103cd565b6040519015158152602001610117565b34801561015c57600080fd5b5061016660025481565b604051908152602001610117565b34801561018057600080fd5b5061014061018f366004610ac3565b610439565b3480156101a057600080fd5b506100ee6101af366004610aff565b610519565b3480156101c057600080fd5b506101e87f000000000000000000000000000000000000000000000000000000000000000081565b60405160ff9091168152602001610117565b34801561020657600080fd5b50610166610565565b34801561021b57600080fd5b5061016661022a366004610b18565b60036020526000908152604090205481565b34801561024857600080fd5b50610166610257366004610b18565b60056020526000908152604090205481565b34801561027557600080fd5b5061010a6105c0565b34801561028a57600080fd5b50610140610299366004610a99565b6105cd565b6100ee6102fe565b3480156102b257600080fd5b506100ee6102c1366004610b3a565b610633565b3480156102d257600080fd5b506101666102e1366004610bad565b600460209081526000928352604080842090915290825290205481565b610308333461087c565b60405134815233907fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c9060200160405180910390a2565b6000805461034c90610be0565b80601f016020809104026020016040519081016040528092919081815260200182805461037890610be0565b80156103c55780601f1061039a576101008083540402835291602001916103c5565b820191906000526020600020905b8154815290600101906020018083116103a857829003601f168201915b505050505081565b3360008181526004602090815260408083206001600160a01b038716808552925280832085905551919290917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925906104289086815260200190565b60405180910390a350600192915050565b6001600160a01b03831660009081526004602090815260408083203384529091528120546000198114610495576104708382610c30565b6001600160a01b03861660009081526004602090815260408083203384529091529020555b6001600160a01b038516600090815260036020526040812080548592906104bd908490610c30565b90915550506001600160a01b0380851660008181526003602052604090819020805487019055519091871690600080516020610cff833981519152906105069087815260200190565b60405180910390a3506001949350505050565b61052333826108d6565b60405181815233907f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b659060200160405180910390a26105623382610938565b50565b60007f0000000000000000000000000000000000000000000000000000000000000000461461059b5761059661098e565b905090565b507f000000000000000000000000000000000000000000000000000000000000000090565b6001805461034c90610be0565b336000908152600360205260408120805483919083906105ee908490610c30565b90915550506001600160a01b03831660008181526003602052604090819020805485019055513390600080516020610cff833981519152906104289086815260200190565b428410156106885760405162461bcd60e51b815260206004820152601760248201527f5045524d49545f444541444c494e455f4558504952454400000000000000000060448201526064015b60405180910390fd5b60006001610694610565565b6001600160a01b038a811660008181526005602090815260409182902080546001810190915582517f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c98184015280840194909452938d166060840152608083018c905260a083019390935260c08083018b90528151808403909101815260e08301909152805192019190912061190160f01b6101008301526101028201929092526101228101919091526101420160408051601f198184030181528282528051602091820120600084529083018083525260ff871690820152606081018590526080810184905260a0016020604051602081039080840390855afa1580156107a0573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b038116158015906107d65750876001600160a01b0316816001600160a01b0316145b6108135760405162461bcd60e51b815260206004820152600e60248201526d24a72b20a624a22fa9a4a3a722a960911b604482015260640161067f565b6001600160a01b0390811660009081526004602090815260408083208a8516808552908352928190208990555188815291928a16917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a350505050505050565b806002600082825461088e9190610c47565b90915550506001600160a01b038216600081815260036020908152604080832080548601905551848152600080516020610cff83398151915291015b60405180910390a35050565b6001600160a01b038216600090815260036020526040812080548392906108fe908490610c30565b90915550506002805482900390556040518181526000906001600160a01b03841690600080516020610cff833981519152906020016108ca565b600080600080600085875af19050806109895760405162461bcd60e51b815260206004820152601360248201527211551217d514905394d1915497d19052531151606a1b604482015260640161067f565b505050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f60006040516109c09190610c5f565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b600060208083528351808285015260005b81811015610a5557858101830151858201604001528201610a39565b81811115610a67576000604083870101525b50601f01601f1916929092016040019392505050565b80356001600160a01b0381168114610a9457600080fd5b919050565b60008060408385031215610aac57600080fd5b610ab583610a7d565b946020939093013593505050565b600080600060608486031215610ad857600080fd5b610ae184610a7d565b9250610aef60208501610a7d565b9150604084013590509250925092565b600060208284031215610b1157600080fd5b5035919050565b600060208284031215610b2a57600080fd5b610b3382610a7d565b9392505050565b600080600080600080600060e0888a031215610b5557600080fd5b610b5e88610a7d565b9650610b6c60208901610a7d565b95506040880135945060608801359350608088013560ff81168114610b9057600080fd5b9699959850939692959460a0840135945060c09093013592915050565b60008060408385031215610bc057600080fd5b610bc983610a7d565b9150610bd760208401610a7d565b90509250929050565b600181811c90821680610bf457607f821691505b602082108103610c1457634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b600082821015610c4257610c42610c1a565b500390565b60008219821115610c5a57610c5a610c1a565b500190565b600080835481600182811c915080831680610c7b57607f831692505b60208084108203610c9a57634e487b7160e01b86526022600452602486fd5b818015610cae5760018114610cc357610cf0565b60ff1986168952841515850289019650610cf0565b60008a81526020902060005b86811015610ce85781548b820152908501908301610ccf565b505084890196505b50949897505050505050505056feddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa26469706673582212205cb1dce9614459fe64bdc49747ff664bbf11bc25efa985d7bc8850dc5b8734df64736f6c634300080f0033";

type WFILConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: WFILConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class WFIL__factory extends ContractFactory {
  constructor(...args: WFILConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<WFIL> {
    return super.deploy(overrides || {}) as Promise<WFIL>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): WFIL {
    return super.attach(address) as WFIL;
  }
  override connect(signer: Signer): WFIL__factory {
    return super.connect(signer) as WFIL__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): WFILInterface {
    return new utils.Interface(_abi) as WFILInterface;
  }
  static connect(address: string, signerOrProvider: Signer | Provider): WFIL {
    return new Contract(address, _abi, signerOrProvider) as WFIL;
  }
}
