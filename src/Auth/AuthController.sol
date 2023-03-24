// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Roles} from "src/Constants/Roles.sol";
import "src/Constants/FuncSigs.sol";

library AuthController {

  error Unauthorized();

  function onlyAgent(address router, address agent) internal view {
    if (!GetRoute.agentFactory(router).isAgent(agent)) {
       revert Unauthorized();
    }
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
