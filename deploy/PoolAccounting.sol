// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {PoolAccounting} from "src/Pool/PoolAccounting.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
// This contract is just used to deploy the PoolAccounting contract
contract PoolAccountingDeployer {

  /**
   * @dev deploys a new PoolAccounting contract
   * @param _id pool id
   * @param _router router address
   * @param _poolImplementation pool implementation address
   * @param _asset staking asset address
   * @param _share pool share token address
   * @param _template pool template address
   * @param _ramp pool off ramp address
   * @param _iou pool IOU token address
   * @param _minimumLiquidity pool minimum liquidity amount
  */
  function deploy(
    uint256 _id,
    address _router,
    address _poolImplementation,
    address _asset,
    address _share,
    address _template,
    address _ramp,
    address _iou,
    uint256 _minimumLiquidity
  ) public returns (IPool) {
    return new PoolAccounting(
      _id,
      _router,
      _poolImplementation,
      _asset,
      _share,
      _template,
      _ramp,
      _iou,
      _minimumLiquidity
    );
  }
}
