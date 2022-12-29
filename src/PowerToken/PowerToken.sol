// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_POOL_FACTORY, ROUTE_AGENT_FACTORY, ROUTE_TREASURY} from "src/Constants/Routes.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Unauthorized} from "src/Errors.sol";

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
      AuthController.requiresSubAuth(router, address(this));
      _;
    }

    modifier onlyAgent() {
      AuthController.onlyAgent(router, msg.sender);
      _;
    }

    modifier validTo(address to) {
      _validTo(to);
      _;
    }

    modifier notPaused() {
      _notPaused();
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
    ) public override(IPowerToken, ERC20) notPaused validTo(to) returns (bool) {
      return super.transfer(to, amount);
    }

    function approve(
      address spender,
      uint256 amount
    ) public override(IPowerToken, ERC20) notPaused validTo(spender) returns (bool) {
      return super.approve(spender, amount);
    }

    function transferFrom(
      address from,
      address to,
      uint256 amount
    ) public override(IPowerToken, ERC20) notPaused validTo(to) returns (bool) {
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

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validTo(address to) internal view {
      IPoolFactory poolFactory = GetRoute.poolFactory(router);
      IAgentFactory agentFactory = GetRoute.agentFactory(router);
      address treasury = IRouter(router).getRoute(ROUTE_TREASURY);

      // to address can be one of:
      // agent
      // pool accounting
      // treasury
      // bool isPoolAccounting = poolFactory.isPool(to);
      // bool isAgent = agentFactory.isAgent(to);
      // bool isTreasury = to == treasury;
      // bool validToAddr = isPoolAccounting || isAgent || isTreasury;

      if (!(
        poolFactory.isPool(to) ||
        agentFactory.isAgent(to) ||
        to == treasury
      )) {
        revert Unauthorized(
          address(this),
          msg.sender,
          msg.sig,
          "PowerToken: Invalid to address"
        );
      }
    }

    function _notPaused() internal view {
      require(!paused, "PowerToken: Contract is paused");
    }
}
