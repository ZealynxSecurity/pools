// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {PoolAccounting} from "src/Pool/PoolAccounting.sol";
import {PoolTemplate} from "src/Pool/PoolTemplate.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_TREASURY} from "src/Constants/Routes.sol";
import {Deployer} from "deploy/Deployer.sol";

contract PoolFactory is IPoolFactory, RouterAware {
  /**
   * @notice The PoolFactoryAdmin can change the treasury fee up to the MAX_TREASURY_FEE
   * @dev treasury fee is denominated by 1e18, in other words, 1e17 is 10% fee
   */
  uint256 public constant MAX_TREASURY_FEE = 1e17;
  uint256 public treasuryFeeRate;
  uint256 public feeThreshold;
  ERC20 public asset;
  address[] public allPools;
  mapping(address => bool) public templates;
  mapping(address => bool) public implementations;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth() virtual {
    AuthController.requiresSubAuth(router, address(this));
    _;
  }

  constructor(
    ERC20 _asset,
    uint256 _treasuryFeeRate,
    uint256 _feeThreshold
  ) {
    asset = _asset;
    treasuryFeeRate = _treasuryFeeRate;
    feeThreshold = _feeThreshold;
  }

  function createSymbol() internal view returns (string memory) {
    bytes memory b;
    b = abi.encodePacked("P");
    b = abi.encodePacked(b, Strings.toString(allPools.length));
    b = abi.encodePacked(b, "GLIF");

    return string(b);
  }

  function allPoolsLength() public view returns (uint256) {
    return allPools.length;
  }

  function createPool(
    string memory name,
    string memory symbol,
    address operator,
    address implementation,
    address template
  ) external requiresAuth returns (IPool pool) {
    address stakingAsset = address(asset);
    require(implementations[implementation], "Pool: Broker not approved");
    require(templates[template], "Pool: Template not approved");

    // Create custom ERC20 for the pools
    // TODO: Token naming - https://github.com/glif-confidential/pools/issues/223
    (
      address shareToken,
      address iouToken,
      address ramp
    ) = Deployer.deployPoolAncillaries(
      router,
      stakingAsset,
      allPools.length,
      name,
      symbol
    );

    pool = new PoolAccounting(
      allPools.length,
      router,
      implementation,
      stakingAsset,
      shareToken,
      template,
      ramp,
      iouToken,
      0
    );

    allPools.push(address(pool));

    AuthController.initPoolRoles(router, address(pool), operator, address(this));
  }

  function isPool(address pool) external view returns (bool) {
    for (uint256 i = 0; i < allPools.length; i++) {
      if (allPools[i] == pool) {
        return true;
      }
    }
    return false;
  }

  function isPoolTemplate(address pool) external view returns (bool) {
    return templates[pool];
  }

  function approveImplementation(address implementation) external requiresAuth {
    implementations[implementation] = true;
  }

  function approveTemplate(address template) external requiresAuth {
    templates[template] = true;
  }

  // TODO: Not sure about side effects of removing live versions? Should be safe - deprecation
  function revokeImplementation(address implementation) external requiresAuth {
    implementations[implementation] = false;
  }

  function revokeTemplate(address template) external requiresAuth {
    templates[template] = false;
  }

  function setTreasuryFeeRate(uint256 newFeeRate) external requiresAuth {
    require(newFeeRate <= MAX_TREASURY_FEE, "Pool: Fee too high");
    treasuryFeeRate = newFeeRate;
  }

  function setFeeThreshold(uint256 newThreshold) external requiresAuth {
    feeThreshold = newThreshold;
  }
}
