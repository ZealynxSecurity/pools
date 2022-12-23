// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_POOL_FACTORY, ROUTE_AGENT_FACTORY} from "src/Constants/Routes.sol";

contract PowerToken is
  IPowerToken,
  RouterAware,
  ERC20("Tokenized Filecoin Power", "POW", 18)
  {
    // @notice this contract can be paused, but we plan to burn the pauser role
    // once the contracts stabilize
    bool public paused = false;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requiresAuth() {
      require(
        RoleAuthority.canCallSubAuthority(router, address(this)),
        "PowerToken: Not authorized"
      );
      _;
    }

    modifier onlyAgent() {
      require(
        IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY)).agents(msg.sender),
        "PowerToken: Not authorized"
      );
      _;
    }

    modifier validFromTo(address from, address to) {
      IPoolFactory poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
      IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));

      // if from is a pool, to must be an agent
      if (poolFactory.isPool(from)) {
        require(agentFactory.agents(to), "PowerToken: Pool can only transfer power tokens to agents");
        _;
      }
      // if from is an agent, to must be a pool
      else if (agentFactory.agents(from)) {
        require(poolFactory.isPool(to), "PowerToken: Agent can only transfer power tokens to pools");
        _;
      } else {
        revert("PowerToken: Invalid transfer");
      }
    }

    modifier notPaused() {
      require(!paused, "PowerToken: Contract is paused");
      _;
    }

    function mint(uint256 _amount) public notPaused onlyAgent {
      _mint(msg.sender, _amount);
      emit MintPower(msg.sender, _amount);
    }

    function burn(uint256 _amount) public notPaused onlyAgent {
      _burn(msg.sender, _amount);
      emit BurnPower(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function transfer(
      address to,
      uint256 amount
    ) public override(IPowerToken, ERC20) notPaused validFromTo(msg.sender, to) returns (bool) {
      return super.transfer(to, amount);
    }

    function approve(
      address spender,
      uint256 amount
    ) public override(IPowerToken, ERC20) notPaused validFromTo(msg.sender, spender) returns (bool) {
      return super.approve(spender, amount);
    }

    function transferFrom(
      address from,
      address to,
      uint256 amount
    ) public override(IPowerToken, ERC20) notPaused validFromTo(from, to) returns (bool) {
      return super.transferFrom(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN CONTROLS
    //////////////////////////////////////////////////////////////*/

    function pause() external requiresAuth {
      paused = true;
      emit PauseContract();
    }

    function resume() external requiresAuth {
      paused = false;
      emit ResumeContract();
    }
}
