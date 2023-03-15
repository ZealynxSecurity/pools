// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {IPowerTokenPlus} from "src/Types/Interfaces/IPowerTokenPlus.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ROUTE_POOL_FACTORY, ROUTE_AGENT_FACTORY, ROUTE_TREASURY} from "src/Constants/Routes.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Unauthorized} from "src/Errors.sol";

contract PowerToken is
  IPowerTokenPlus,
  RouterAware,
  ERC20("Tokenized Filecoin Power", "POW", 18)
  {
    // @notice this contract can be paused, but we plan to burn the pauser role
    // once the contracts stabilize
    bool public paused = false;
    mapping(uint256 => uint256) public powerTokensMinted;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/



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

    /*//////////////////////////////////////////////////////////////
                          MINT/BURN POWER
    //////////////////////////////////////////////////////////////*/

    function mint(uint256 _amount) public notPaused onlyAgent {
      powerTokensMinted[_addressToID(msg.sender)] += _amount;

      _mint(msg.sender, _amount);
      emit MintPower(msg.sender, _amount);
    }

    function burn(uint256 _amount) public notPaused onlyAgent {
      powerTokensMinted[_addressToID(msg.sender)] -= _amount;

      _burn(msg.sender, _amount);
      emit BurnPower(msg.sender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function transfer(
      address to,
      uint256 amount
    ) public override notPaused validTo(to) returns (bool) {
      return super.transfer(to, amount);
    }

    function approve(
      address spender,
      uint256 amount
    ) public override notPaused validTo(spender) returns (bool) {
      return super.approve(spender, amount);
    }

    function transferFrom(
      address from,
      address to,
      uint256 amount
    ) public override notPaused validTo(to) returns (bool) {
      return super.transferFrom(from, to, amount);
    }

    function permit(
      address owner,
      address spender,
      uint256 amount,
      uint256 deadline,
      uint8 v,
      bytes32 r,
      bytes32 s
    ) public override notPaused validTo(spender) {
      super.permit(owner, spender, amount, deadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN CONTROLS
    //////////////////////////////////////////////////////////////*/

    function pause() external {
      paused = true;
      emit PauseContract();
    }

    function resume() external {
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
        revert Unauthorized();
      }
    }

    function _notPaused() internal view {
      require(!paused, "PowerToken: Contract is paused");
    }

    function _addressToID(address agent) internal view returns (uint256) {
      return IAgent(agent).id();
    }
}
