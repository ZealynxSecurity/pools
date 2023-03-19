// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {GenesisPool} from "src/Pool/Genesis.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
// This contract is just used to deploy the GenesisPool contract
contract GenesisPoolDeployer {

  /**
   * @dev deploys a new GenesisPool contract
   * @param _owner pool owner address
   * @param _operator pool operator address
   * @param _id pool id
   * @param _router router address
   * @param _asset staking asset address
   * @param _share pool share token address
   * @param _ramp pool off ramp address
   * @param _iou pool IOU token address
   * @param _minimumLiquidity pool minimum liquidity amount
   * @param _bias the curve constant of the dynamic rate

  */
  function deploy(
    address _owner,
    address _operator,
    uint256 _id,
    address _router,
    address _asset,
    address _share,
    address _ramp,
    address _iou,
    uint256 _minimumLiquidity,
    uint256 _bias
  ) public returns (IPool) {
    return new GenesisPool(
      _owner,
      _operator,
      _id,
      _router,
      _asset,
      _share,
      _ramp,
      _iou,
      _minimumLiquidity,
      _bias
    );
  }
}
