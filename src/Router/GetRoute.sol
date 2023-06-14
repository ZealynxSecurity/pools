// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentDeployer} from "src/Types/Interfaces/IAgentDeployer.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {ICredentials} from "src/Types/Interfaces/ICredentials.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import "src/Constants/Routes.sol";

library GetRoute {
  error InvalidPoolID();

  function agentFactory(address router) internal view returns (IAgentFactory) {
    return IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
  }

  function agentDeployer(address router) internal view returns (IAgentDeployer) {
    return IAgentDeployer(IRouter(router).getRoute(ROUTE_AGENT_DEPLOYER));
  }

  function poolRegistry(address router) internal view returns (IPoolRegistry) {
    return IPoolRegistry(IRouter(router).getRoute(ROUTE_POOL_REGISTRY));
  }

  function credParser(address router) internal view returns (ICredentials) {
    return ICredentials(IRouter(router).getRoute(ROUTE_CRED_PARSER));
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

  function pool(IPoolRegistry poolReg, uint256 poolID) internal view returns (IPool) {
    if (poolID > poolReg.allPoolsLength()) revert InvalidPoolID();
    return IPool(poolReg.allPools(poolID));
  }

  function treasury(address router) internal view returns (address) {
    return IRouter(router).getRoute(ROUTE_TREASURY);
  }
}
