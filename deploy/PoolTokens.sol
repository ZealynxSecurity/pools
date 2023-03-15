// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Router} from "src/Router/Router.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";

library PoolTokensDeployer {

  /**
   *  @dev this function creates the necessary surrounding contracts for Pool deployment
   *  @notice its set public - this is to reduce the bytecode size of the PoolFactory
   *  this function does not get embedded into the calling contract, reducing its bytesize
   */
  function deploy(
    address router,
    uint256 poolID,
    string memory name,
    string memory symbol
  ) public returns (
    address shareToken,
    address iouToken
  ) {
    // Create custom ERC20 for the pools
    shareToken = address(new PoolToken(
      router,
      poolID,
      name,
      symbol
    ));
    iouToken = address(new PoolToken(
      router,
      poolID,
      name,
      symbol
    ));
  }
}
