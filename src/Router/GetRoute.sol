// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import "src/Constants/Routes.sol";

library GetRoute {
  function agentFactory(address router) internal view returns (IAgentFactory) {
    return IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
  }

  function poolFactory(address router) internal view returns (IPoolFactory) {
    return IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
  }

  function powerToken(address router) internal view returns (IPowerToken) {
    return IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
  }

  function powerToken20(address router) internal view returns (IERC20) {
    return IERC20(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
  }

  function wFIL(address router) internal view returns (IWFIL) {
    return IWFIL(IRouter(router).getRoute(ROUTE_WFIL_TOKEN));
  }

  function wFIL20(address router) internal view returns (IERC20) {
    return IERC20(IRouter(router).getRoute(ROUTE_WFIL_TOKEN));
  }

  function minerRegistry(address router) internal view returns (IMinerRegistry) {
    return IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
  }

  function agentPolice(address router) internal view returns (IAgentPolice) {
    return IAgentPolice(IRouter(router).getRoute(ROUTE_AGENT_POLICE));
  }

  // NOTE - the agent police _is_ a vcverifier singleton
  function vcVerifier(address router) internal view returns (IVCVerifier) {
    return IVCVerifier(IRouter(router).getRoute(ROUTE_AGENT_POLICE));
  }

  function pool(address router, uint256 poolID) internal view returns (IPool) {
    IPoolFactory _poolFactory = poolFactory(router);
    require(poolID <= _poolFactory.allPoolsLength(), "Invalid pool ID");
    return IPool(_poolFactory.allPools(poolID));
  }
}
