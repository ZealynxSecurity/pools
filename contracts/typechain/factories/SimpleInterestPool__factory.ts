/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import {
  Signer,
  utils,
  Contract,
  ContractFactory,
  BigNumberish,
  Overrides,
} from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common";
import type {
  SimpleInterestPool,
  SimpleInterestPoolInterface,
} from "../SimpleInterestPool";

const _abi = [
  {
    inputs: [
      {
        internalType: "contract ERC20",
        name: "_asset",
        type: "address",
      },
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
        internalType: "uint256",
        name: "poolID",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "baseRate",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "treasury",
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
        name: "caller",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "shares",
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
        name: "caller",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "receiver",
        type: "address",
      },
      {
        indexed: true,
        internalType: "address",
        name: "owner",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    name: "Withdraw",
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
    inputs: [],
    name: "asset",
    outputs: [
      {
        internalType: "contract ERC20",
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
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "loanAgent",
        type: "address",
      },
    ],
    name: "borrow",
    outputs: [
      {
        internalType: "uint256",
        name: "interest",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    name: "convertToAssets",
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
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
    ],
    name: "convertToShares",
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
    inputs: [
      {
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "receiver",
        type: "address",
      },
    ],
    name: "deposit",
    outputs: [
      {
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "fee",
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
    name: "feeFlushAmt",
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
    name: "feesCollected",
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
    name: "flush",
    outputs: [],
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
    name: "getFee",
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
        name: "borrower",
        type: "address",
      },
    ],
    name: "getLoan",
    outputs: [
      {
        components: [
          {
            internalType: "uint256",
            name: "startEpoch",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "periods",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "principal",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "interest",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "totalPaid",
            type: "uint256",
          },
        ],
        internalType: "struct Loan",
        name: "loan",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "id",
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
    name: "interestRate",
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
        name: "borrower",
        type: "address",
      },
    ],
    name: "loanBalance",
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
    name: "loanPeriods",
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
        name: "",
        type: "address",
      },
    ],
    name: "maxDeposit",
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
        name: "",
        type: "address",
      },
    ],
    name: "maxMint",
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
    ],
    name: "maxRedeem",
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
    ],
    name: "maxWithdraw",
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
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "receiver",
        type: "address",
      },
    ],
    name: "mint",
    outputs: [
      {
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
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
    inputs: [
      {
        components: [
          {
            internalType: "uint256",
            name: "startEpoch",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "periods",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "principal",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "interest",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "totalPaid",
            type: "uint256",
          },
        ],
        internalType: "struct Loan",
        name: "_loan",
        type: "tuple",
      },
    ],
    name: "pmtPerEpoch",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "pure",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
    ],
    name: "previewDeposit",
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
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    name: "previewMint",
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
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    name: "previewRedeem",
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
        internalType: "uint256",
        name: "assets",
        type: "uint256",
      },
    ],
    name: "previewWithdraw",
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
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "receiver",
        type: "address",
      },
      {
        internalType: "address",
        name: "owner",
        type: "address",
      },
    ],
    name: "redeem",
    outputs: [
      {
        internalType: "uint256",
        name: "assets",
        type: "uint256",
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
      {
        internalType: "address",
        name: "loanAgent",
        type: "address",
      },
      {
        internalType: "address",
        name: "payee",
        type: "address",
      },
    ],
    name: "repay",
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
    name: "totalAssets",
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
        components: [
          {
            internalType: "uint256",
            name: "startEpoch",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "periods",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "principal",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "interest",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "totalPaid",
            type: "uint256",
          },
        ],
        internalType: "struct Loan",
        name: "_loan",
        type: "tuple",
      },
    ],
    name: "totalLoanValue",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "pure",
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
    inputs: [],
    name: "treasury",
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
        name: "assets",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "receiver",
        type: "address",
      },
      {
        internalType: "address",
        name: "owner",
        type: "address",
      },
    ],
    name: "withdraw",
    outputs: [
      {
        internalType: "uint256",
        name: "shares",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const _bytecode =
  "0x6101006040526217bb006009556658d15e17628000600a556000600b55670de0b6b3a7640000600c553480156200003557600080fd5b50604051620021783803806200217883398101604081905262000058916200033c565b8585858585858585858181846001600160a01b031663313ce5676040518163ffffffff1660e01b8152600401602060405180830381865afa158015620000a2573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620000c89190620003e4565b6000620000d6848262000498565b506001620000e5838262000498565b5060ff81166080524660a052620000fb6200016d565b60c052505050506001600160a01b039190911660e052506007839055620001388268056bc75e2d6310000062000209602090811b620013f917901c565b600855600680546001600160a01b0319166001600160a01b039290921691909117905550620005e29950505050505050505050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f6000604051620001a1919062000564565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b60006200022083670de0b6b3a76400008462000227565b9392505050565b8282028115158415858304851417166200024057600080fd5b6001826001830304018115150290509392505050565b6001600160a01b03811681146200026c57600080fd5b50565b634e487b7160e01b600052604160045260246000fd5b600082601f8301126200029757600080fd5b81516001600160401b0380821115620002b457620002b46200026f565b604051601f8301601f19908116603f01168101908282118183101715620002df57620002df6200026f565b81604052838152602092508683858801011115620002fc57600080fd5b600091505b8382101562000320578582018301518183018401529082019062000301565b83821115620003325760008385830101525b9695505050505050565b60008060008060008060c087890312156200035657600080fd5b8651620003638162000256565b60208801519096506001600160401b03808211156200038157600080fd5b6200038f8a838b0162000285565b96506040890151915080821115620003a657600080fd5b50620003b589828a0162000285565b945050606087015192506080870151915060a0870151620003d68162000256565b809150509295509295509295565b600060208284031215620003f757600080fd5b815160ff811681146200022057600080fd5b600181811c908216806200041e57607f821691505b6020821081036200043f57634e487b7160e01b600052602260045260246000fd5b50919050565b601f8211156200049357600081815260208120601f850160051c810160208610156200046e5750805b601f850160051c820191505b818110156200048f578281556001016200047a565b5050505b505050565b81516001600160401b03811115620004b457620004b46200026f565b620004cc81620004c5845462000409565b8462000445565b602080601f831160018114620005045760008415620004eb5750858301515b600019600386901b1c1916600185901b1785556200048f565b600085815260208120601f198616915b82811015620005355788860151825594840194600190910190840162000514565b5085821015620005545787850151600019600388901b60f8161c191681555b5050505050600190811b01905550565b6000808354620005748162000409565b600182811680156200058f5760018114620005a557620005d6565b60ff1984168752821515830287019450620005d6565b8760005260208060002060005b85811015620005cd5781548a820152908401908201620005b2565b50505082870194505b50929695505050505050565b60805160a05160c05160e051611b24620006546000396000818161039e0152818161063701528181610aeb01528181610b6501528181610c3001528181610cc801528181610f350152818161107701526110fe0152600061099501526000610965015260006103080152611b246000f3fe608060405234801561001057600080fd5b50600436106102695760003560e01c80637c3a00fd11610151578063c63d75b6116100c3578063d905777e11610087578063d905777e14610593578063dd62ed3e146105bc578063ddca3f43146105e7578063ef8b30f7146105f0578063f071db5a14610603578063fcee45f41461060c57600080fd5b8063c63d75b6146103d8578063c6e6f59214610547578063c883b2e51461055a578063ce96cb771461056d578063d505accf1461058057600080fd5b8063a9059cbb11610115578063a9059cbb146104e9578063ac8c8a49146104fc578063af640d0f14610505578063b3d7f6b91461050e578063b460af9414610521578063ba0876521461053457600080fd5b80637c3a00fd146104925780637ecebe001461049b57806394bf804d146104bb57806395d89b41146104ce5780639aae66f9146104d657600080fd5b806338d52e0f116101ea5780634ce2611d116101ae5780634ce2611d146104265780635400a34e1461043957806361d027b3146104425780636b9f96ea146104555780636e553f651461045f57806370a082311461047257600080fd5b806338d52e0f14610399578063402d267d146103d85780634ad7004d146103ed5780634b3fd148146104005780634cdad5061461041357600080fd5b806318160ddd1161023157806318160ddd146102e757806323b872dd146102f0578063313ce5671461030357806333481fc91461033c5780633644e5151461039157600080fd5b806301e1d1141461026e57806306fdde031461028957806307a2d13a1461029e578063095ea7b3146102b15780630a28a477146102d4575b600080fd5b61027661061f565b6040519081526020015b60405180910390f35b6102916106af565b60405161028091906116c8565b6102766102ac36600461171d565b61073d565b6102c46102bf366004611752565b61076a565b6040519015158152602001610280565b6102766102e236600461171d565b6107d7565b61027660025481565b6102c46102fe36600461177c565b6107f7565b61032a7f000000000000000000000000000000000000000000000000000000000000000081565b60405160ff9091168152602001610280565b61034f61034a3660046117b8565b6108d7565b6040516102809190600060a082019050825182526020830151602083015260408301516040830152606083015160608301526080830151608083015292915050565b610276610961565b6103c07f000000000000000000000000000000000000000000000000000000000000000081565b6040516001600160a01b039091168152602001610280565b6102766103e63660046117b8565b5060001990565b6102766103fb3660046117d3565b6109b7565b61027661040e366004611851565b6109e3565b61027661042136600461171d565b610b12565b6102766104343660046117d3565b610b1d565b61027660095481565b6006546103c0906001600160a01b031681565b61045d610b33565b005b61027661046d366004611851565b610bd8565b6102766104803660046117b8565b60036020526000908152604090205481565b61027660085481565b6102766104a93660046117b8565b60056020526000908152604090205481565b6102766104c9366004611851565b610cae565b610291610d3d565b6102766104e43660046117b8565b610d4a565b6102c46104f7366004611752565b610dd3565b610276600c5481565b61027660075481565b61027661051c36600461171d565b610e39565b61027661052f36600461187d565b610e58565b61027661054236600461187d565b610f5c565b61027661055536600461171d565b61109e565b61045d61056836600461187d565b6110be565b61027661057b3660046117b8565b611178565b61045d61058e3660046118b9565b61119a565b6102766105a13660046117b8565b6001600160a01b031660009081526003602052604090205490565b6102766105ca36600461192c565b600460209081526000928352604080842090915290825290205481565b610276600a5481565b6102766105fe36600461171d565b6113de565b610276600b5481565b61027661061a36600461171d565b6113e9565b6040516370a0823160e01b81523060048201526000907f00000000000000000000000000000000000000000000000000000000000000006001600160a01b0316906370a0823190602401602060405180830381865afa158015610686573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906106aa9190611956565b905090565b600080546106bc9061196f565b80601f01602080910402602001604051908101604052809291908181526020018280546106e89061196f565b80156107355780601f1061070a57610100808354040283529160200191610735565b820191906000526020600020905b81548152906001019060200180831161071857829003601f168201915b505050505081565b60025460009080156107615761075c61075461061f565b84908361140e565b610763565b825b9392505050565b3360008181526004602090815260408083206001600160a01b038716808552925280832085905551919290917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925906107c59086815260200190565b60405180910390a35060015b92915050565b60025460009080156107615761075c816107ef61061f565b85919061142d565b6001600160a01b038316600090815260046020908152604080832033845290915281205460001981146108535761082e83826119bf565b6001600160a01b03861660009081526004602090815260408083203384529091529020555b6001600160a01b0385166000908152600360205260408120805485929061087b9084906119bf565b90915550506001600160a01b0380851660008181526003602052604090819020805487019055519091871690600080516020611acf833981519152906108c49087815260200190565b60405180910390a3506001949350505050565b6109096040518060a0016040528060008152602001600081526020016000815260200160008152602001600081525090565b506001600160a01b03166000908152600d6020908152604091829020825160a0810184528154815260018201549281019290925260028101549282019290925260038201546060820152600490910154608082015290565b60007f00000000000000000000000000000000000000000000000000000000000000004614610992576106aa61145b565b507f000000000000000000000000000000000000000000000000000000000000000090565b60006107d18260200151670de0b6b3a76400006109d491906119d6565b6109dd84610b1d565b906113f9565b60006109ed61061f565b831115610a715760405162461bcd60e51b815260206004820152604160248201527f416d6f756e7420746f20626f72726f77206d757374206265206c65737320746860448201527f616e207468697320706f6f6c2773206c697175696420746f74616c41737365746064820152607360f81b608482015260a4015b60405180910390fd5b600854610a7f9084906114f5565b6040805160a0810182524381526009546020808301918252828401888152606084018681526000608086018181526001600160a01b03808c168352600d90955296902094518555925160018501555160028401559051600383015591516004909101559091506107d1907f000000000000000000000000000000000000000000000000000000000000000016838561150a565b60006107d18261073d565b6000816060015182604001516107d191906119f5565b600b8054600090915560065460405163a9059cbb60e01b81526001600160a01b039182166004820152602481018390527f00000000000000000000000000000000000000000000000000000000000000009091169063a9059cbb906044016020604051808303816000875af1158015610bb0573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190610bd49190611a0d565b5050565b6000610be3836113de565b905080600003610c235760405162461bcd60e51b815260206004820152600b60248201526a5a45524f5f53484152455360a81b6044820152606401610a68565b610c586001600160a01b037f000000000000000000000000000000000000000000000000000000000000000016333086611582565b610c62828261160c565b60408051848152602081018390526001600160a01b0384169133917fdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d791015b60405180910390a36107d1565b6000610cb983610e39565b9050610cf06001600160a01b037f000000000000000000000000000000000000000000000000000000000000000016333084611582565b610cfa828461160c565b60408051828152602081018590526001600160a01b0384169133917fdcbc1c05240f31ff3ad067ef1ee35ce4997762752e3a095284754544f4c709d79101610ca1565b600180546106bc9061196f565b600080610d56836108d7565b8051909150600003610d6b5750600092915050565b8051600090610d7a90436119bf565b90506000610da2610d8a846109b7565b610d9c84670de0b6b3a76400006119d6565b906114f5565b90508260800151811115610dc8576080830151610dbf90826119bf565b95945050505050565b506000949350505050565b33600090815260036020526040812080548391908390610df49084906119bf565b90915550506001600160a01b03831660008181526003602052604090819020805485019055513390600080516020611acf833981519152906107c59086815260200190565b60025460009080156107615761075c610e5061061f565b84908361142d565b6000610e63846107d7565b9050336001600160a01b03831614610ed3576001600160a01b03821660009081526004602090815260408083203384529091529020546000198114610ed157610eac82826119bf565b6001600160a01b03841660009081526004602090815260408083203384529091529020555b505b610edd8282611666565b60408051858152602081018390526001600160a01b03808516929086169133917ffbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db910160405180910390a46107636001600160a01b037f000000000000000000000000000000000000000000000000000000000000000016848661150a565b6000336001600160a01b03831614610fcc576001600160a01b03821660009081526004602090815260408083203384529091529020546000198114610fca57610fa585826119bf565b6001600160a01b03841660009081526004602090815260408083203384529091529020555b505b610fd584610b12565b9050806000036110155760405162461bcd60e51b815260206004820152600b60248201526a5a45524f5f41535345545360a81b6044820152606401610a68565b61101f8285611666565b60408051828152602081018690526001600160a01b03808516929086169133917ffbde797d201c681b91056529119e0b02407c7bb96a4a2c75c01fc9667232c8db910160405180910390a46107636001600160a01b037f000000000000000000000000000000000000000000000000000000000000000016848361150a565b60025460009080156107615761075c816110b661061f565b85919061140e565b6001600160a01b0382166000908152600d60205260408120600481018054919286926110eb9084906119f5565b9091555061112690506001600160a01b037f000000000000000000000000000000000000000000000000000000000000000016833087611582565b600c54611132856113e9565b600b5461113f91906119f5565b11156111525761114d610b33565b611172565b61115b846113e9565b600b600082825461116c91906119f5565b90915550505b50505050565b6001600160a01b0381166000908152600360205260408120546107d19061073d565b428410156111ea5760405162461bcd60e51b815260206004820152601760248201527f5045524d49545f444541444c494e455f455850495245440000000000000000006044820152606401610a68565b600060016111f6610961565b6001600160a01b038a811660008181526005602090815260409182902080546001810190915582517f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c98184015280840194909452938d166060840152608083018c905260a083019390935260c08083018b90528151808403909101815260e08301909152805192019190912061190160f01b6101008301526101028201929092526101228101919091526101420160408051601f198184030181528282528051602091820120600084529083018083525260ff871690820152606081018590526080810184905260a0016020604051602081039080840390855afa158015611302573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b038116158015906113385750876001600160a01b0316816001600160a01b0316145b6113755760405162461bcd60e51b815260206004820152600e60248201526d24a72b20a624a22fa9a4a3a722a960911b6044820152606401610a68565b6001600160a01b0390811660009081526004602090815260408083208a8516808552908352928190208990555188815291928a16917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a350505050505050565b60006107d18261109e565b600a546000906107d190836114f5565b600061076383670de0b6b3a76400008461142d565b82820281151584158583048514171661142657600080fd5b0492915050565b82820281151584158583048514171661144557600080fd5b6001826001830304018115150290509392505050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f600060405161148d9190611a2f565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b60006107638383670de0b6b3a764000061142d565b600060405163a9059cbb60e01b8152836004820152826024820152602060006044836000895af13d15601f3d11600160005114161716915050806111725760405162461bcd60e51b815260206004820152600f60248201526e1514905394d1915497d19052531151608a1b6044820152606401610a68565b60006040516323b872dd60e01b81528460048201528360248201528260448201526020600060648360008a5af13d15601f3d11600160005114161716915050806116055760405162461bcd60e51b81526020600482015260146024820152731514905394d1915497d19493d357d1905253115160621b6044820152606401610a68565b5050505050565b806002600082825461161e91906119f5565b90915550506001600160a01b038216600081815260036020908152604080832080548601905551848152600080516020611acf83398151915291015b60405180910390a35050565b6001600160a01b0382166000908152600360205260408120805483929061168e9084906119bf565b90915550506002805482900390556040518181526000906001600160a01b03841690600080516020611acf8339815191529060200161165a565b600060208083528351808285015260005b818110156116f5578581018301518582016040015282016116d9565b81811115611707576000604083870101525b50601f01601f1916929092016040019392505050565b60006020828403121561172f57600080fd5b5035919050565b80356001600160a01b038116811461174d57600080fd5b919050565b6000806040838503121561176557600080fd5b61176e83611736565b946020939093013593505050565b60008060006060848603121561179157600080fd5b61179a84611736565b92506117a860208501611736565b9150604084013590509250925092565b6000602082840312156117ca57600080fd5b61076382611736565b600060a082840312156117e557600080fd5b60405160a0810181811067ffffffffffffffff8211171561181657634e487b7160e01b600052604160045260246000fd5b806040525082358152602083013560208201526040830135604082015260608301356060820152608083013560808201528091505092915050565b6000806040838503121561186457600080fd5b8235915061187460208401611736565b90509250929050565b60008060006060848603121561189257600080fd5b833592506118a260208501611736565b91506118b060408501611736565b90509250925092565b600080600080600080600060e0888a0312156118d457600080fd5b6118dd88611736565b96506118eb60208901611736565b95506040880135945060608801359350608088013560ff8116811461190f57600080fd5b9699959850939692959460a0840135945060c09093013592915050565b6000806040838503121561193f57600080fd5b61194883611736565b915061187460208401611736565b60006020828403121561196857600080fd5b5051919050565b600181811c9082168061198357607f821691505b6020821081036119a357634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b6000828210156119d1576119d16119a9565b500390565b60008160001904831182151516156119f0576119f06119a9565b500290565b60008219821115611a0857611a086119a9565b500190565b600060208284031215611a1f57600080fd5b8151801515811461076357600080fd5b600080835481600182811c915080831680611a4b57607f831692505b60208084108203611a6a57634e487b7160e01b86526022600452602486fd5b818015611a7e5760018114611a9357611ac0565b60ff1986168952841515850289019650611ac0565b60008a81526020902060005b86811015611ab85781548b820152908501908301611a9f565b505084890196505b50949897505050505050505056feddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa26469706673582212209b258d4cac569504870470a65ff6f757f94f2f5ed2e6da0c91a46acd8342643564736f6c634300080f0033";

type SimpleInterestPoolConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: SimpleInterestPoolConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class SimpleInterestPool__factory extends ContractFactory {
  constructor(...args: SimpleInterestPoolConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _asset: PromiseOrValue<string>,
    _name: PromiseOrValue<string>,
    _symbol: PromiseOrValue<string>,
    poolID: PromiseOrValue<BigNumberish>,
    baseRate: PromiseOrValue<BigNumberish>,
    treasury: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<SimpleInterestPool> {
    return super.deploy(
      _asset,
      _name,
      _symbol,
      poolID,
      baseRate,
      treasury,
      overrides || {}
    ) as Promise<SimpleInterestPool>;
  }
  override getDeployTransaction(
    _asset: PromiseOrValue<string>,
    _name: PromiseOrValue<string>,
    _symbol: PromiseOrValue<string>,
    poolID: PromiseOrValue<BigNumberish>,
    baseRate: PromiseOrValue<BigNumberish>,
    treasury: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(
      _asset,
      _name,
      _symbol,
      poolID,
      baseRate,
      treasury,
      overrides || {}
    );
  }
  override attach(address: string): SimpleInterestPool {
    return super.attach(address) as SimpleInterestPool;
  }
  override connect(signer: Signer): SimpleInterestPool__factory {
    return super.connect(signer) as SimpleInterestPool__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): SimpleInterestPoolInterface {
    return new utils.Interface(_abi) as SimpleInterestPoolInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): SimpleInterestPool {
    return new Contract(address, _abi, signerOrProvider) as SimpleInterestPool;
  }
}
