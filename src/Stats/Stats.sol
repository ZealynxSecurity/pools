// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IPoolFactory} from "src/Pool/PoolFactory.sol";
import {IPool4626} from "src/Pool/IPool4626.sol";
import {ILoanAgentFactory} from "src/LoanAgent/LoanAgentFactory.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Router} from "src/Router/Router.sol";

contract Stats is RouterAware {
  function getPoolFactory() internal view returns (IPoolFactory) {
    return IPoolFactory(Router(router).getPoolFactory());
  }

  function getLoanAgentFactory() internal view returns (ILoanAgentFactory) {
    return ILoanAgentFactory(Router(router).getLoanAgentFactory());
  }

  function isDebtor(address loanAgent) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      (uint256 bal,) = IPool4626(poolFactory.allPools(i)).loanBalance(loanAgent);
      if (bal > 0) {
        return true;
      }
    }
    return false;
  }

  function isDebtor(address loanAgent, uint256 poolID) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    (uint256 bal,) = IPool4626(poolFactory.allPools(poolID)).loanBalance(loanAgent);
    if (bal > 0) {
      return true;
    }
    return false;
  }

  function hasPenalties(address loanAgent) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    for (uint256 i = 0; i < poolFactory.allPoolsLength(); ++i) {
      (,uint256 penalty) = IPool4626(poolFactory.allPools(i)).loanBalance(loanAgent);
      if (penalty > 0) {
        return true;
      }
    }
    return false;
  }

  function hasPenalties(address loanAgent, uint256 poolID) public view returns (bool) {
    IPoolFactory poolFactory = getPoolFactory();
    (,uint256 penalty) = IPool4626(poolFactory.allPools(poolID)).loanBalance(loanAgent);
    if (penalty > 0) {
      return true;
    }

    return false;
  }

  function isLoanAgent(address loanAgent) public view returns (bool) {
    return getLoanAgentFactory().loanAgents(loanAgent);
  }
}
