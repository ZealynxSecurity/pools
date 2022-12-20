// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {MultiRolesAuthority} from "src/Auth/MultiRolesAuthority.sol";
import {IMultiRolesAuthority} from "src/Auth/IMultiRolesAuthority.sol";
import {Authority, Auth} from "src/Auth/Auth.sol";
import {IRouter} from "src/Router/IRouter.sol";
import {ROUTE_CORE_AUTHORITY} from "src/Router/Routes.sol";
import {AGENT_MINT_POWER_SELECTOR} from "src/Constants/FuncSigs.sol";
import "src/Constants/Roles.sol";
import "src/Constants/FuncSigs.sol";

library RoleAuthority {
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

  function initFactoryRoles(
    address router,
    address agentFactory,
    address agentFactoryAdmin,
    address poolFactory,
    address poolFactoryAdmin
  ) internal {
    IMultiRolesAuthority authority = getCoreAuthority(router);
    // factories needs to be able to assign custom Authorities on a per agent/pool basis
    authority.setUserRole(agentFactory, ROLE_AGENT_FACTORY, true);
    authority.setUserRole(poolFactory, ROLE_POOL_FACTORY, true);
    authority.setRoleCapability(
      ROLE_AGENT_FACTORY, AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, true
    );
    authority.setRoleCapability(
      ROLE_POOL_FACTORY, AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR, true
    );

    // create factory specific sub authorities
    MultiRolesAuthority agentFactoryAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, agentFactory, agentFactoryAuthority);

    MultiRolesAuthority poolFactoryAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, poolFactory, poolFactoryAuthority);

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
    address powerTokenAdmin,
    // the agentFactory must be able to set AGENT role on the power token
    address agentFactory
  ) internal {
    // calling contract starts as the owner of the sub authority so we can add roles and capabilities
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, powerToken, subAuthority);

    // set necessary roles
    subAuthority.setUserRole(powerTokenAdmin, ROLE_POWER_TOKEN_ADMIN, true);
    subAuthority.setUserRole(agentFactory, ROLE_AGENT_FACTORY, true);

    // set necessary role capabilities
    // Power token admin can pause/unpause the contract
    subAuthority.setRoleCapability(ROLE_POWER_TOKEN_ADMIN, POWER_TOKEN_PAUSE_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_POWER_TOKEN_ADMIN, POWER_TOKEN_RESUME_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT_FACTORY, AUTH_SET_USER_ROLE_SELECTOR, true);

    // Agents can mint/burn power tokens
    subAuthority.setRoleCapability(ROLE_AGENT, POWER_TOKEN_MINT_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT, POWER_TOKEN_BURN_SELECTOR, true);

    // change the owner of the sub authority to the power token admin
    subAuthority.transferOwnership(powerTokenAdmin);
  }

  function initAgentRoles(
    address router,
    address agent,
    address operator,
    address powerToken,
    address vcIssuer,
    address minerRegistry
    ) internal {
      MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
      setSubAuthority(router, agent, subAuthority);

      // the miner registry's Authority must know about this agent
      IMultiRolesAuthority(address(getSubAuthority(router, minerRegistry)))
      .setUserRole(agent, ROLE_AGENT, true);

      // the power token's Authority must know about this agent too
      IMultiRolesAuthority(address(getSubAuthority(router, powerToken)))
      .setUserRole(agent, ROLE_AGENT, true);

      // the agent is a VCVerifier, which needs to know who is the VC_ISSUER
      subAuthority.setUserRole(vcIssuer, ROLE_VC_ISSUER, true);

      subAuthority.setUserRole(agent, ROLE_AGENT, true);
      subAuthority.setUserRole(msg.sender, ROLE_AGENT_OWNER, true);
      if (operator == address(0)) {
        subAuthority.setUserRole(msg.sender, ROLE_AGENT_OPERATOR, true);
      } else {
        subAuthority.setUserRole(operator, ROLE_AGENT_OPERATOR, true);
      }


      // AGENT_OPERATOR can operate the Agent, but not change operators
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_ADD_MINER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_REMOVE_MINER_ADDR_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_REMOVE_MINER_INDEX_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_REVOKE_OWNERSHIP_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_MINT_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_BURN_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_WITHDRAW_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_BORROW_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_REPAY_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_MINT_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OPERATOR, AGENT_BURN_POWER_SELECTOR, true);

      // AGENT_OWNER role can call all functions that the operator can, but can also enable / disable operators & owners
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_ENABLE_OPERATOR_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_DISABLE_OPERATOR_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_ENABLE_OWNER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_DISABLE_OWNER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_ADD_MINER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_REMOVE_MINER_ADDR_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_REMOVE_MINER_INDEX_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_REVOKE_OWNERSHIP_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_MINT_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_BURN_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_WITHDRAW_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_BORROW_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_REPAY_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_MINT_POWER_SELECTOR, true);
      subAuthority.setRoleCapability(ROLE_AGENT_OWNER, AGENT_BURN_POWER_SELECTOR, true);

      // NOTE - these capabilities are needed in order for the Agent to be able to set roles on itself
      // used for changing the pseudo owner / operator
      subAuthority.setRoleCapability(ROLE_AGENT, AUTH_SET_USER_ROLE_SELECTOR, true);

      // set the owner of the agent's authority to be the agent
      subAuthority.transferOwnership(agent);
  }

  function initRouterRoles(address router, address routerAdmin) internal {
    IMultiRolesAuthority authority = getCoreAuthority(router);
    // set necessary roles
    authority.setUserRole(routerAdmin, ROLE_ROUTER_ADMIN, true);

    authority.setRoleCapability(ROLE_ROUTER_ADMIN, ROUTER_PUSH_ROUTE_BYTES_SELECTOR, true);
    authority.setRoleCapability(ROLE_ROUTER_ADMIN, ROUTER_PUSH_ROUTE_STRING_SELECTOR, true);
    authority.setRoleCapability(ROLE_ROUTER_ADMIN, ROUTER_PUSH_ROUTES_BYTES_SELECTOR, true);
    authority.setRoleCapability(ROLE_ROUTER_ADMIN, ROUTER_PUSH_ROUTES_STRING_SELECTOR, true);
  }

  function initMinerRegistryRoles(
    address router,
    address minerRegistry,
    address minerRegistryAdmin,
    address agentFactory
  ) internal {
    MultiRolesAuthority subAuthority = newMultiRolesAuthority(address(this), Authority(address(0)));
    setSubAuthority(router, minerRegistry, subAuthority);

    // set necessary roles
    subAuthority.setUserRole(agentFactory, ROLE_AGENT_FACTORY, true);

    // set necessary capabilities
    subAuthority.setRoleCapability(ROLE_AGENT_FACTORY, AUTH_SET_USER_ROLE_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT, MINER_REGISTRY_ADD_MINER_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT, MINER_REGISTRY_RM_MINER_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT, MINER_REGISTRY_ADD_MINERS_SELECTOR, true);
    subAuthority.setRoleCapability(ROLE_AGENT, MINER_REGISTRY_RM_MINERS_SELECTOR, true);

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
