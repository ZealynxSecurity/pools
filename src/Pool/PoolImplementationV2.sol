// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {AccountV2} from "src/Types/Structs/Account.sol";
import {AccountHelpersV2} from "src/Pool/AccountV2.sol";
import {IPoolImplementationV2} from "src/Types/Interfaces/IPoolImplementation.sol";
import {Ownable} from "src/Auth/Ownable.sol";

contract PoolImplementationV2 is IPoolImplementationV2, Ownable {
  using AccountHelpersV2 for AccountV2;

  /// @dev `bias` sets the curve for the interest rate
  uint256 bias;

  constructor(
    address _owner,
    uint256 _bias
  ) Ownable(_owner) {
    bias = _bias;
  }

  /**
   * @notice getRate returns the rate for an Agent's current position within the Pool
   * rate = inflation adjusted base rate * (bias * (100 - GCRED))
   */
  function getRate(
      AccountV2 memory account,
      VerifiableCredential memory vc
  ) external view returns (uint256) {
    // return vc.baseRate * e**(bias * (100 - vc.gcred))
    return 15e16;
  }

  function isOverLeveraged(
    AccountV2 memory account,
    VerifiableCredential memory vc
  ) external view returns (bool) {
    // equity percentage
    // your portion of agents assets = equity percentage * vc.agentTotalValue
    // ltv = (account.principal + account.paymentsDue) / your portion of agents assets
    // dti =
    return false;
  }
}
