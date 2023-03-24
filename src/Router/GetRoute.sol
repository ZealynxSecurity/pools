// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentDeployer} from "src/Types/Interfaces/IAgentDeployer.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
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

  function agentDeployer(address router) internal view returns (IAgentDeployer) {
    return IAgentDeployer(IRouter(router).getRoute(ROUTE_AGENT_DEPLOYER));
  }

  function poolFactory(address router) internal view returns (IPoolFactory) {
    return IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
  }

  function wFIL(address router) internal view returns (IWFIL) {
    return IWFIL(IRouter(router).getRoute(ROUTE_WFIL_TOKEN));
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

  function treasury(address router) internal view returns (address) {
    return IRouter(router).getRoute(ROUTE_TREASURY);
  }
}
