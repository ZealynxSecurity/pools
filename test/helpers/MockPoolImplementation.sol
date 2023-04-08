// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

// import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
// import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
// import {Account} from "src/Types/Structs/Account.sol";
// import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
// import {RouterAware} from "src/Router/RouterAware.sol";
// import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

// contract MockPoolImplementation is IPoolImplementation, RouterAware {
//   using FixedPointMathLib for uint256;

//   uint256 rate;

//   constructor (uint256 _rate, address _router) {
//     rate = _rate;
//     router = _router;
//   }

//   function getRate(
//     uint256 ,
//     uint256 ,
//     uint256 ,
//     Account memory,
//     VerifiableCredential memory
//   ) external pure returns (uint256) {
//     // hardcode 20% rate (per annum)
//     uint256 apy = 0.2e18;
//     return apy / EPOCHS_IN_YEAR;
//   }

//   function rateSpike(
//     uint256 ,
//     uint256 ,
//     Account memory
//   ) external pure returns (uint256) {
//     uint256 penalty = 5e16;
//     return penalty / EPOCHS_IN_YEAR;
//   }

//   function minCollateral(
//     Account memory account,
//     VerifiableCredential memory
//   ) external pure returns (uint256) {
//     // 10% of the borrow amount
//     return account.totalBorrowed.mulWadUp(1e17);
//   }

//   function beforeBorrow(
//     uint256 ,
//     uint256 ,
//     Account memory ,
//     VerifiableCredential memory
//   ) external pure {}

//   function beforeExit(
//       uint256 ,
//       Account memory ,
//       VerifiableCredential memory
//   ) external pure {}

//   function beforeMakePayment(
//       uint256 ,
//       Account memory
//   ) external pure {}
// }
