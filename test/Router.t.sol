// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "src/Router/Router.sol";
import "src/Router/Routes.sol";

contract RouterTest is Test {
  Router router;
  address agentFactory;
  address poolFactory;
  address vcVerifier;
  address stats;
  address minerRegistry;
  address authority;
  address powerToken;
  address wfilToken;
  function setUp() public {
    agentFactory = makeAddr("AGENT_FACTORY");
    poolFactory = makeAddr("POOL_FACTORY");
    vcVerifier = makeAddr("VC_VERIFIER");
    stats = makeAddr("STATS");
    minerRegistry = makeAddr("MINER_REGISTRY");
    authority = makeAddr("AUTHORITY");
    powerToken = makeAddr("POWER_TOKEN");

    router = new Router(
      agentFactory,
      poolFactory,
      vcVerifier,
      stats,
      minerRegistry,
      authority,
      powerToken
    );
  }

  function testGetAgentFactory() public {
    assertEq(router.getRoute(Routes.AGENT_FACTORY), agentFactory);
  }

  function testGetPoolFactory() public {
    assertEq(router.getRoute(Routes.POOL_FACTORY), poolFactory);
  }

  function testGetVCVerifier() public {
    assertEq(router.getRoute(Routes.VC_VERIFIER), vcVerifier);
  }

  function testGetStats() public {
    assertEq(router.getRoute(Routes.STATS), stats);
  }

  function testGetMinerRegistry() public {
    assertEq(router.getRoute(Routes.MINER_REGISTRY), minerRegistry);
  }

  function testGetAuthority() public {
    assertEq(router.getRoute(Routes.AUTHORITY), authority);
  }

  function testGetPowerToken() public {
    assertEq(router.getRoute(Routes.POWER_TOKEN), powerToken);
  }

  function testPushRoute() public {
    address newRoute = makeAddr("NEW_ROUTE");
    router.pushRoute(Routes.AGENT_FACTORY, newRoute);
    assertEq(router.getRoute(Routes.AGENT_FACTORY), newRoute);
  }

  function testPushRouteString() public {
    address newRoute = makeAddr("TEST_ROUTE");
    router.pushRoute("TEST_ROUTE", newRoute);
    assertEq(router.getRoute("TEST_ROUTE"), newRoute);
  }
}
