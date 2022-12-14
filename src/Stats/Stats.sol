// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPoolFactory} from "src/Pool/IPoolFactory.sol";
import {IPool4626} from "src/Pool/IPool4626.sol";
import {IAgentFactory} from "src/Agent/AgentFactory.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Router} from "src/Router/Router.sol";

contract Stats is RouterAware {
  function getPoolFactory() internal view returns (IPoolFactory) {
    return IPoolFactory(Router(router).getPoolFactory());
  }

  function getAgentFactory() internal view returns (IAgentFactory) {
    return IAgentFactory(Router(router).getAgentFactory());
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
