// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {GetRoute} from "src/Router/GetRoute.sol";

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

  function onlyPoolRegistry(address router, address poolRegistry) internal view {
    if (address(GetRoute.poolRegistry(router)) != poolRegistry) {
      revert Unauthorized();
    }
  }

  function onlyAgentFactory(address router, address agentFactory) internal view {
    if (address(GetRoute.agentFactory(router)) != agentFactory) {
      revert Unauthorized();
    }
  }
}
