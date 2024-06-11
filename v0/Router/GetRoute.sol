// SPDX-License-Identifier: UNLICENSED
// solhint-disable
pragma solidity 0.8.17;

import {IRouter} from "v0/Types/Interfaces/IRouter.sol";
import {IAgentFactory} from "v0/Types/Interfaces/IAgentFactory.sol";
import {IAgentDeployer} from "v0/Types/Interfaces/IAgentDeployer.sol";
import {IPoolRegistry} from "v0/Types/Interfaces/IPoolRegistry.sol";
import {IMinerRegistry} from "v0/Types/Interfaces/IMinerRegistry.sol";
import {ICredentials} from "v0/Types/Interfaces/ICredentials.sol";
import {IERC20} from "v0/Types/Interfaces/IERC20.sol";
import {IPool} from "v0/Types/Interfaces/IPool.sol";
import {IWFIL} from "v0/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "v0/Types/Interfaces/IAgentPolice.sol";
import {IVCVerifier} from "v0/Types/Interfaces/IVCVerifier.sol";
import "v0/Constants/Routes.sol";

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
