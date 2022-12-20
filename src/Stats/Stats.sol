// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {RouterAware} from "src/Router/RouterAware.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_POOL_FACTORY, ROUTE_AGENT_FACTORY} from "src/Constants/Routes.sol";

contract Stats is RouterAware {
  function isDebtor(address agent) public view returns (bool) {
    IPoolFactory poolFactory = _getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      if (_getPool(i).nextDueDate(agent) < block.number) {
        return true;
      }
    }
    return false;
  }

  function isDebtor(address agent, uint256 poolID) public view returns (bool) {
    IPool pool = _getPool(poolID);
    if (pool.nextDueDate(agent) < block.number) {
      return true;
    }
    return false;
  }

  function hasPenalties(address agent) public view returns (bool) {
    IPoolFactory poolFactory = _getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      if (_getPool(i).nextDueDate(agent) < block.number) {
        return true;
      }
    }
    return false;
  }

  function hasPenalties(address agent, uint256 poolID) public view returns (bool) {
    IPoolFactory poolFactory = _getPoolFactory();
    // Check pool for penalties

    return false;
  }

  function isAgent(address agent) public view returns (bool) {
    return _getAgentFactory().agents(agent);
  }


  function _getPool(uint256 poolID) internal view returns (IPool) {
    return IPool(IPoolFactory(_getPoolFactory()).allPools(poolID));
  }

  function _getPoolFactory() internal view returns (IPoolFactory) {
    return IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
  }

  function _getAgentFactory() internal view returns (IAgentFactory) {
    return IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
  }
}
