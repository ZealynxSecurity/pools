// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IOffRamp {

  /*//////////////////////////////////////////////////
                        EVENTS
  //////////////////////////////////////////////////*/

    //   event GovernanceUpdated(
    //     address governance
    // );

    // event PendingGovernanceUpdated(
    //     address pendingGovernance
    // );

  event TransmuterPeriodUpdated(
      uint256 newTransmutationPeriod
  );

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  function conversionWindow() external view returns (uint256);

  function iouToken() external view returns (address);

  function totalIOUStaked() external view returns (uint256);

  function totalExitDemand() external view returns (uint256);

  function asset() external view returns (address);

  function iouTokensStaked(address) external view returns (uint256);

  function iouTokensToRealize(address) external view returns (uint256);

  function assetsToClaim(address) external view returns (uint256);

  function lastAccountUpdateCursor(address) external view returns (uint256);

  function userIsKnown(address) external view returns (bool);

  function userList(uint256) external view returns (address);

  function liquidAssets() external view returns (uint256);

  function lastDepositBlock() external view returns (uint256);

  function totalDividendPoints() external view returns (uint256);

  function unclaimedDividends() external view returns (uint256);

  function dividendsOwing(address) external view returns (uint256);

  function userInfo(address user) external view returns (
    uint256 stakedIOUs,
    uint256 pendingDivs,
    uint256 realizeableIOUs,
    uint256 claimableIOUs
  );

  function getMultipleUserInfo(
    uint256 from,
    uint256 to
  ) external view returns (
    address[] memory theUserList,
    uint256[] memory theUserData
  );

  function bufferInfo() external view returns (
    uint256 toDistribute,
    uint256 deltaBlocks,
    uint256 canDistribute
  );

  /*//////////////////////////////////////////////////
                  STATE CHANGING METHODS
  //////////////////////////////////////////////////*/

  function distribute(address receiver, uint256 amount) external;

  function stake(uint256 amount) external;

  function unstake(uint256 amount) external;

  function realize() external;

  function forceRealize(address victim) external;

  function claim() external;

  function exit() external;

  function realizeAndClaim() external;

  function realizeClaimAndWithdraw() external;

  function setConversionWindow(uint256 newConversionWindow) external;

  function maxWithdraw(address account) external view returns (uint256);

  function maxRedeem(address account) external view returns (uint256);

  function previewWithdraw(uint256 assets) external view returns (uint256);

  function previewRedeem(uint256 assets) external view returns (uint256);

  function redeem(
    uint256 shares,
    address receiver,
    address owner,
    uint256 totalAssets
  ) external  returns (uint256 assets);

  function withdraw(
      uint256 assets,
      address receiver,
      address owner,
      uint256 totalAssets
  ) external returns (uint256 shares);
}

