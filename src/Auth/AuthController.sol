// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {ROUTE_CORE_AUTHORITY} from "src/Constants/Routes.sol";
import {Roles} from "src/Constants/Roles.sol";
import {Unauthorized} from "src/Errors.sol";
import "src/Constants/FuncSigs.sol";

library AuthController {

  function onlyAgent(address router, address agent) internal view {
    require(
      GetRoute.agentFactory(router).isAgent(agent),
      "onlyAgent: Not authorized"
    );
  }

  function onlyAgentPolice(address router, address agentPolice) internal view {
    if (address(GetRoute.agentPolice(router)) != agentPolice) {
      revert Unauthorized();
    }
  }

  function onlyPoolAccounting(address router, address poolAccounting) internal view {
    require(
      GetRoute.poolFactory(router).isPool(poolAccounting),
      "onlyPoolAccounting: Not authorized"
    );
  }

  function onlyPoolFactory(address router, address poolFactory) internal view {
    if (address(GetRoute.poolFactory(router)) != poolFactory) {
      revert Unauthorized();
    }
  }

  function onlyAgentFactory(address router, address agentFactory) internal view {
    if (address(GetRoute.agentFactory(router)) != agentFactory) {
      revert Unauthorized();
    }
  }
}
