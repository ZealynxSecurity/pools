// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {Authority, Auth} from "src/Auth/Auth.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {ROUTE_CORE_AUTHORITY} from "src/Constants/Routes.sol";
import {Roles} from "src/Constants/Roles.sol";
import {Unauthorized} from "src/Errors.sol";
import "src/Constants/FuncSigs.sol";

library AuthController {
  function newMultiRolesAuthority(
    address owner,
    Authority auth
  ) internal returns (MultiRolesAuthority) {
    MultiRolesAuthority mra = new MultiRolesAuthority(owner, auth);
    // if no authority is set, set the authority to itself
    if (address(auth) == address(0)) {
      mra.setAuthority(mra);
    }

    return mra;
  }

  function getCoreAuthority(address router) internal view returns (IMultiRolesAuthority) {
    return IMultiRolesAuthority(IRouter(router).getRoute(ROUTE_CORE_AUTHORITY));
  }

  function getSubAuthority(address router, address target) internal view returns (Authority) {
    // All Authorities in our system are MultiRolesAuthority
    return Authority(address(getCoreAuthority(router).getTargetCustomAuthority(target)));
  }

  function canCall(address router, address target) internal view returns (bool) {
    IMultiRolesAuthority cAuthority = getCoreAuthority(router);
    return Auth(address(cAuthority)).owner() == msg.sender
    || cAuthority.canCall(msg.sender, target, msg.sig);
  }

  function canCallAuthority(Authority authority, address target) internal view returns (bool) {
    return Auth(address(authority)).owner() == msg.sender
    || authority.canCall(msg.sender, target, msg.sig);
  }

  function canCallSubAuthority(address router, address subAuthority) internal view returns (bool) {
    return canCallAuthority(getSubAuthority(router, subAuthority), subAuthority);
  }

  function requiresCoreAuth(address router, address target) internal view {
    require(
      canCall(router, target),
      "requiresCoreAuth: Not authorized"
    );
  }

  function requiresSubAuth(address router, address subAuthority) internal view {
    require(
      AuthController.canCallSubAuthority(router, subAuthority),
      "requiresSubAuth: Not authorized"
    );
  }

  function onlyAgent(address router, address agent) internal view {
    require(
      GetRoute.agentFactory(router).isAgent(agent),
      "onlyAgent: Not authorized"
    );
  }

  function onlyAgentPolice(address router, address agentPolice) internal view {
    if (!(address(GetRoute.agentPolice(router)) == agentPolice)) {
      revert Unauthorized(
        address(this),
        agentPolice,
        msg.sig,
        "onlyAgentPolice: Not authorized"
      );
    }
  }

  function onlyPoolAccounting(address router, address poolAccounting) internal view {
    require(
      GetRoute.poolFactory(router).isPool(poolAccounting),
      "onlyPoolAccounting: Not authorized"
    );
  }

  function onlyPoolTemplate(address router, address poolTemplate) internal view {
    require(
      GetRoute.poolFactory(router).isPoolTemplate(poolTemplate),
      "onlyPoolTemplate: Not authorized"
    );
  }

  function initFactoryRoles(
    address router,
    address agentFactory,
    address agentFactoryAdmin,
    address poolFactory,
    address poolFactoryAdmin,
    address poolDeployer
  ) internal {
    IMultiRolesAuthority authority = getCoreAuthority(router);
    // factories needs to be able to assign custom Authorities on a per agent/pool basis
    authority.setUserRole(agentFactory, uint8(uint8(Roles.ROLE_AGENT_FACTORY)), true);
    authority.setUserRole(poolFactory, uint8(uint8(Roles.ROLE_POOL_FACTORY)), true);
    authority.setRoleCapability(
      uint8(uint8(Roles.ROLE_AGENT_FACTORY)), AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, true
    );
    authority.setRoleCapability(
      uint8(uint8(Roles.ROLE_POOL_FACTORY)), AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, true
    );

    // create factory specific sub authorities
    MultiRolesAuthority agentFactoryAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, agentFactory, agentFactoryAuthority);

    MultiRolesAuthority poolFactoryAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, poolFactory, poolFactoryAuthority);

    // Setup custom roles and capabilities for the pool factory
    poolFactoryAuthority.setUserRole(poolDeployer, uint8(Roles.ROLE_POOL_DEPLOYER), true);

    bytes4[5] memory deployerCapabilities = [
      POOL_FACTORY_CREATE_POOL_SELECTOR,
      POOL_FACTORY_APPROVE_IMPLEMENTATION_SELECTOR,
      POOL_FACTORY_REVOKE_IMPLEMENTATION_SELECTOR,
      POOL_FACTORY_APPROVE_TEMPLATE_SELECTOR,
      POOL_FACTORY_REVOKE_TEMPLATE_SELECTOR
    ];

    for (uint256 i = 0; i < deployerCapabilities.length; ++i) {
      poolFactoryAuthority.setRoleCapability(
        uint8(Roles.ROLE_POOL_DEPLOYER), deployerCapabilities[i], true
      );
    }

    agentFactoryAuthority.transferOwnership(agentFactoryAdmin);
    poolFactoryAuthority.transferOwnership(poolFactoryAdmin);
  }

  function setSubAuthority (
    address router,
    address target,
    Authority customAuthority
    ) internal {
      getCoreAuthority(router).setTargetCustomAuthority(target, customAuthority);
  }

  function initPowerTokenRoles(
    address router,
    address powerToken,
    address powerTokenAdmin
  ) internal {
    // calling contract starts as the owner of the sub authority so we can add roles and capabilities
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, powerToken, subAuthority);

    // change the owner of the sub authority to the power token admin
    subAuthority.transferOwnership(powerTokenAdmin);
  }

  function initPoolRoles(
    address router,
    address pool,
    address operator,
    address poolFactory
  ) internal {
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, pool, subAuthority);

    // pool factory is able to draw up funds from the pool
    subAuthority.setUserRole(poolFactory, uint8(Roles.ROLE_POOL_FACTORY), true);
    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL_FACTORY), POOL_FLUSH_SELECTOR, true);

    // pool itself should be able to add roles to its own authority
    // in order to allow for enabling/disabling operators
    subAuthority.setUserRole(pool, uint8(Roles.ROLE_POOL), true);
    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL), AUTH_SET_USER_ROLE_SELECTOR, true);

    subAuthority.setUserRole(msg.sender, uint8(Roles.ROLE_POOL_OWNER), true);
    if (operator == address(0)) {
      subAuthority.setUserRole(msg.sender, uint8(Roles.ROLE_POOL_OPERATOR), true);
    } else {
      subAuthority.setUserRole(operator, uint8(Roles.ROLE_POOL_OPERATOR), true);
    }

    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL_OWNER), POOL_ENABLE_OPERATOR_SELECTOR, true);
    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL_OWNER), POOL_DISABLE_OPERATOR_SELECTOR, true);

    // TODO: should this be possible?
    // TODO: Should operator be able to change the rate module?
    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL_OPERATOR), POOL_SET_RATE_MODULE_SELECTOR, true);
    subAuthority.setRoleCapability(uint8(Roles.ROLE_POOL_OPERATOR), POOL_SET_RATE_MODULE_SELECTOR, true);

    subAuthority.transferOwnership(msg.sender);
  }

  function initAgentPoliceRoles(
    address router,
    address agentPolice,
    address admin
  ) internal {
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, agentPolice, subAuthority);

    subAuthority.transferOwnership(admin);
  }

  function initAgentRoles(
    address router,
    address agent,
    address operator
  ) internal {
      MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
      setSubAuthority(router, agent, subAuthority);

      subAuthority.setUserRole(agent, uint8(Roles.ROLE_AGENT), true);
      subAuthority.setUserRole(msg.sender, uint8(Roles.ROLE_AGENT_OWNER), true);
      subAuthority.setUserRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR), true);

      bytes4[12] memory commonSelectors = [
        // miner funcs
        AGENT_ADD_MINERS_SELECTOR,
        AGENT_REMOVE_MINER_SELECTOR,
        AGENT_CHANGE_MINER_WORKER_SELECTOR,
        AGENT_CHANGE_MINER_MULTIADDRS_SELECTOR,
        AGENT_CHANGE_MINER_PEERID_SELECTOR,
        // finance funcs
        AGENT_BORROW_SELECTOR,
        AGENT_EXIT_SELECTOR,
        AGENT_MAKE_PAYMENTS_SELECTOR,
        AGENT_PULL_FUNDS_SELECTOR,
        AGENT_PUSH_FUNDS_SELECTOR,
        // power token funcs
        AGENT_MINT_POWER_SELECTOR,
        AGENT_BURN_POWER_SELECTOR
      ];

      // shared capabilities for both operator and owner
      for (uint i = 0; i < commonSelectors.length; ++i) {
        subAuthority.setRoleCapability(uint8(Roles.ROLE_AGENT_OPERATOR), commonSelectors[i], true);
        subAuthority.setRoleCapability(uint8(Roles.ROLE_AGENT_OWNER), commonSelectors[i], true);
      }

      bytes4[4] memory ownerOnlySelectors = [
        SET_OPERATOR_ROLE_SELECTOR,
        SET_OWNER_ROLE_SELECTOR,
        AGENT_WITHDRAW_SELECTOR,
        AGENT_WITHDRAW_WITH_CRED_SELECTOR
      ];

      for (uint i = 0; i < ownerOnlySelectors.length; ++i) {
        subAuthority.setRoleCapability(uint8(Roles.ROLE_AGENT_OWNER), ownerOnlySelectors[i], true);
      }

      // NOTE - these capabilities are needed in order for the Agent to be able to set roles on itself
      // used for changing the pseudo owner / operator
      subAuthority.setRoleCapability(uint8(Roles.ROLE_AGENT), AUTH_SET_USER_ROLE_SELECTOR, true);

      // set the owner of the agent's authority to be the agent
      subAuthority.transferOwnership(agent);
  }

  function initMinerRegistryRoles(
    address router,
    address minerRegistry,
    address minerRegistryAdmin
  ) internal {
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, minerRegistry, subAuthority);

    subAuthority.transferOwnership(minerRegistryAdmin);
  }

  function transferCoreAuthorityOwnership(address router, address systemAdmin) internal {
    // dont retransfer ownership if it already exists
    if (msg.sender == systemAdmin || systemAdmin == address(0)) {
      return;
    }

    Auth(address(getCoreAuthority(router))).transferOwnership(systemAdmin);
  }
}
