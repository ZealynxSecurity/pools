// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

contract RateArrayGenerator is Script {

  uint256 immutable BASE_RATE = 18e16;

  // includes a rate for GCRED 40-100, so 61 values
  uint256[61] public rateArray;

  using FixedPointMathLib for uint256;

  constructor() {
    // maps GCRED => annual rate
    // subtract 39 from the GCRED to get the index
    rateArray[40 - 40]  =  40e16;
    rateArray[41 - 40]  =  39.5e16;
    rateArray[42 - 40]  =  39.0e16;
    rateArray[43 - 40]  =  38.5e16;
    rateArray[44 - 40]  =  38.0e16;
    rateArray[45 - 40]  =  37.5e16;
    rateArray[46 - 40]  =  37.0e16;
    rateArray[47 - 40]  =  36.5e16;
    rateArray[48 - 40]  =  36.0e16;
    rateArray[49 - 40]  =  35.5e16;
    rateArray[50 - 40]  =  34e16;
    rateArray[51 - 40]  =  33.5e16;
    rateArray[52 - 40]  =  33.0e16;
    rateArray[53 - 40]  =  32.5e16;
    rateArray[54 - 40]  =  32.0e16;
    rateArray[55 - 40]  =  31.5e16;
    rateArray[56 - 40]  =  31.0e16;
    rateArray[57 - 40]  =  30.5e16;
    rateArray[58 - 40]  =  30.0e16;
    rateArray[59 - 40]  =  29.5e16;
    rateArray[60 - 40]  =  29e16;
    rateArray[61 - 40]  =  28.6e16;
    rateArray[62 - 40]  =  28.2e16;
    rateArray[63 - 40]  =  27.8e16;
    rateArray[64 - 40]  =  27.4e16;
    rateArray[65 - 40]  =  27.0e16;
    rateArray[66 - 40]  =  26.6e16;
    rateArray[67 - 40]  =  26.2e16;
    rateArray[68 - 40]  =  25.8e16;
    rateArray[69 - 40]  =  25.4e16;
    rateArray[70 - 40]  =  25e16;
    rateArray[71 - 40]  =  24.7e16;
    rateArray[72 - 40]  =  24.4e16;
    rateArray[73 - 40]  =  24.1e16;
    rateArray[74 - 40]  =  23.8e16;
    rateArray[75 - 40]  =  23.5e16;
    rateArray[76 - 40]  =  23.2e16;
    rateArray[77 - 40]  =  22.9e16;
    rateArray[78 - 40]  =  22.6e16;
    rateArray[79 - 40]  =  22.3e16;
    rateArray[80 - 40]  =  22e16;
    rateArray[81 - 40]  =  21.8e16;
    rateArray[82 - 40]  =  21.6e16;
    rateArray[83 - 40]  =  21.4e16;
    rateArray[84 - 40]  =  21.2e16;
    rateArray[85 - 40]  =  20.0e16;
    rateArray[86 - 40]  =  20.8e16;
    rateArray[87 - 40]  =  20.6e16;
    rateArray[88 - 40]  =  20.4e16;
    rateArray[89 - 40]  =  20.2e16;
    rateArray[90 - 40]  =  20e16;
    rateArray[91 - 40]  =  19.8e16;
    rateArray[92 - 40]  =  19.6e16;
    rateArray[93 - 40]  =  19.4e16;
    rateArray[94 - 40]  =  19.2e16;
    rateArray[95 - 40]  =  19.0e16;
    rateArray[96 - 40]  =  18.8e16;
    rateArray[97 - 40]  =  18.6e16;
    rateArray[98 - 40]  =  18.4e16;
    rateArray[99 - 40]  =  18.2e16;
    rateArray[100 - 40]  =  18e16;
  }

  function run() public view {
    console.log("~~~ Generating rate array ~~~");

    uint256[61] memory rateMultipliers;

    console.log("[");
    for (uint256 i = 0; i < rateArray.length; i++) {
      uint256 rate = rateArray[i];
      if (rate > 0) {
        uint256 multiplier = generateMultiplier(rate);
        rateMultipliers[i] = multiplier;
        console.log(multiplier, ",");
      } else {
        console.log(0, ",");
      }
    }
    console.log("]");


  }

  function generateMultiplier(uint256 rate) internal pure returns (uint256) {
    uint256 annualMultiplier = rate.divWadDown(BASE_RATE);
    uint256 multiplier = annualMultiplier.divWadDown(EPOCHS_IN_YEAR);
    return multiplier;
  }
}
