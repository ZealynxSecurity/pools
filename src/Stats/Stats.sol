// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPoolFactory} from "src/Pool/IPoolFactory.sol";
import {IPool4626} from "src/Pool/IPool4626.sol";
import {IAgentFactory} from "src/Agent/IAgentFactory.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Router/IRouter.sol";
import {ROUTE_POOL_FACTORY, ROUTE_AGENT_FACTORY} from "src/Router/Routes.sol";

contract Stats is RouterAware {
  function getPoolFactory() internal view returns (IPoolFactory) {
    return IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
  }

  function getAgentFactory() internal view returns (IAgentFactory) {
    return IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
  }

  function isDebtor(address agent) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      (uint256 bal,) = IPool4626(poolFactory.allPools(i)).loanBalance(agent);
      if (bal > 0) {
        return true;
      }
    }
    return false;
  }

  function isDebtor(address agent, uint256 poolID) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    (uint256 bal,) = IPool4626(poolFactory.allPools(poolID)).loanBalance(agent);
    if (bal > 0) {
      return true;
    }
    return false;
  }

  function hasPenalties(address agent) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      (,uint256 penalty) = IPool4626(poolFactory.allPools(i)).loanBalance(agent);
      if (penalty > 0) {
        return true;
      }
    }
    return false;
  }

  function hasPenalties(address agent, uint256 poolID) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    (,uint256 penalty) = IPool4626(poolFactory.allPools(poolID)).loanBalance(agent);
    if (penalty > 0) {
      return true;
    }

    return false;
  }

  function isAgent(address agent) public view returns (bool) {
    return getAgentFactory().agents(agent);
  }
}
