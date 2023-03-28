// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

interface IRateModule {
  function credParser() external view returns (address);

  function lookupRate(uint256 gcred) external view returns (uint256);

  function getRate(
      Account memory account,
      VerifiableCredential memory vc
  ) external view returns (uint256);

  function isApproved(
      Account memory account,
      VerifiableCredential memory vc
  ) external view returns (bool);

  function setMaxDTI(uint256 _maxDTI) external;

  function setMaxLTV(uint256 _maxLTV) external;

  function setMinGCRED(uint256 _minGCRED) external;

  function setRateLookup(uint256[100] memory _rateLookup) external;

  function updateCredParser() external;
}
