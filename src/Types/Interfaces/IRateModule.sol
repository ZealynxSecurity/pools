// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

interface IRateModule {

  function maxDTI() external view returns (uint256);

  function maxDTE() external view returns (uint256);

  function maxLTV() external view returns (uint256);

  function minGCRED() external view returns (uint256);

  function credParser() external view returns (address);

  function getRate(
      Account memory account,
      VerifiableCredential memory vc
  ) external view returns (uint256);

  function baseRate() external view returns (uint256);

  function penaltyRate() external view returns (uint256);

  function isApproved(
      Account memory account,
      VerifiableCredential memory vc
  ) external view returns (bool);

  function computeLTV(
      uint256 totalPrincipal,
      uint256 collateralValue
  ) external pure returns (uint256 ltv);

  function computeDTI(
      uint256 expectedDailyRewards,
      uint256 rate,
      uint256 accountPrincipal,
      uint256 totalPrincipal
  ) external pure returns (uint256 dti);

  function computeDTE(
      uint256 accountPrincipal,
      uint256 agentValue
  ) external pure returns (uint256 dte);

  function setMaxDTI(uint256 _maxDTI) external;

  function setMaxLTV(uint256 _maxLTV) external;

  function setMinGCRED(uint256 _minGCRED) external;

  function setRateLookup(uint256[61] memory _rateLookup) external;

  function updateCredParser() external;
}
