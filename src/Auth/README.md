# GLIF Pools Authority and Roles system

GLIF Pools relies on [transmissions11 multi roles authority system](https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/MultiRolesAuthority.sol) - a flexible and target agnostic role based Authority that supports up to 256 roles.

In general, the POOLS architecture follows the following rules:

- The **core authority** provides the top level auth and delegates auth for each contract to specific **sub authorities**.
  - The only exception to this rule is our Router - the Router's Authority _is_ the Core Authority.
- Roles and capabilities are not _cascading_ - in other words, just because you have a specific role or capability on one authority does _not_ imply you have the same role or capability on another authority, no exceptions.
- Within a single authority, the `owner` of that Authority is able to call any protected method.
  - The only exception to this rule is the Power Token - the `owner` of the power token may not call _all_ protected methods, only certain specific ones.<br />


```
    +-------------------------+             +--------------------------+
    |                         |             |                          |
    |    **CORE AUTHORITY**   |-------------|  POWER TOKEN AUTHORITY   |
    |                         |             |                          |
    +-------------------------+             +--------------------------+
                              |
                              |             +--------------------------+
                              |             |                          |
                              |-------------| MINER REGISTRY AUTHORITY |
                              |             |                          |
                              |             +--------------------------+
                              |
                              |             +--------------------------+          +--------------------------+
                              |             |                          |          |                          |
                              --------------- AGENT FACTORY AUTHORITY  |----------|    PER AGENT AUTHORITY   |
                              |             |                          |          |                          |
                              |             +--------------------------+          +--------------------------+
                              |
                              |             +--------------------------+          +--------------------------+
                              |             |                          |          |                          |
                              ---------------  POOL FACTORY AUTHORITY  |----------|     PER POOL AUTHORITY   |
                                            |                          |          |                          |
                                            +--------------------------+          +--------------------------+
```

`/src/Constants/Roles.sol` is the place to look for the most up to date role information.<br />
`/src/Auth/RoleAuthority.sol` is a library that exposes an API for interacting with the roles system

Below is a table that describes the available roles, and their various capabilities. Roles and capabilities have to be discussed on a _per authority basis_.

Two routes should be called special attention to:

1. `AUTH_SET_USER_ROLE_SELECTOR` - if a role has this capability, it can add roles for other users to the given authority.
2. `AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR` - if a role has this capability, it can add custom authorities for targets to the given authority. This is primarily used by the factories, so they can assign new custom targets for each custom authority they deploy for each agent/pool.



| Authority | Role       | Capabilities (each capability corresponds to 1 function call) |
|-----------|------------|--------------|
| **Core** | ROLE_SYSTEM_ADMIN | - OWNER |
| **Core** |  ROLE_ROUTER_ADMIN    | - ROUTER_PUSH_ROUTE_BYTES_SELECTOR<br /> - ROUTER_PUSH_ROUTE_STRING_SELECTOR<br />  - ROUTER_PUSH_ROUTES_BYTES_SELECTOR<br /> - ROUTER_PUSH_ROUTES_STRING_SELECTOR |
| **Core** | ROLE_POOL_FACTORY | - AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR |
| **Core** | ROLE_AGENT_FACTORY | - AUTH_SET_TARGET_CUSTOM_AUTHORITY_SELECTOR |
| **Core** | ROLE_AGENT_FACTORY_ADMIN | - AGENT_FACTORY_SET_VERIFIER_NAME_SELECTOR |
|**Miner Registry** | ROLE_MINER_REGISTRY_ADMIN | - OWNER |
|**Miner Registry** | ROLE_AGENT_FACTORY | - AUTH_SET_USER_ROLE_SELECTOR |
|**Miner Registry** | ROLE_AGENT | - MINER_REGISTRY_ADD_MINER_SELECTOR<br /> - MINER_REGISTRY_RM_MINER_SELECTOR<br /> - MINER_REGISTRY_ADD_MINERS_SELECTOR<br /> - MINER_REGISTRY_RM_MINERS_SELECTOR |
| **Power Token** | ROLE_POWER_TOKEN_ADMIN | - OWNER (not full access)<br /> - POWER_TOKEN_PAUSE_SELECTOR<br /> - POWER_TOKEN_RESUME_SELECTOR |
| **Power Token** | ROLE_AGENT_FACTORY | - AUTH_SET_USER_ROLE_SELECTOR |
| **Power Token** | ROLE_AGENT | - POWER_TOKEN_MINT_SELECTOR<br />- POWER_TOKEN_BURN_SELECTOR |
| **Agent** | ROLE_VC_ISSUER | - ISSUE OFF-CHAIN VERIFIABLE CREDENTIALS |
| **Agent** | ROLE_AGENT_OPERATOR |  - AGENT_ADD_MINER_SELECTOR<br /> - AGENT_REMOVE_MINER_ADDR_SELECTOR<br /> - AGENT_REMOVE_MINER_INDEX_SELECTOR<br /> - AGENT_REVOKE_OWNERSHIP_SELECTOR<br /> - AGENT_MINT_POWER_SELECTOR<br /> - AGENT_BURN_POWER_SELECTOR<br /> - AGENT_WITHDRAW_SELECTOR<br /> - AGENT_BORROW_SELECTOR<br /> - AGENT_REPAY_SELECTOR<br /> - AGENT_MINT_POWER_SELECTOR<br /> - AGENT_BURN_POWER_SELECTOR<br /> |
| **Agent** | ROLE_AGENT_OWNER | - ENABLE_OPERATOR_SELECTOR<br /> - DISABLE_OPERATOR_SELECTOR<br /> - AGENT_ADD_MINER_SELECTOR<br /> - AGENT_REMOVE_MINER_ADDR_SELECTOR<br /> - AGENT_REMOVE_MINER_INDEX_SELECTOR<br /> - AGENT_REVOKE_OWNERSHIP_SELECTOR<br /> - AGENT_MINT_POWER_SELECTOR<br /> - AGENT_BURN_POWER_SELECTOR<br /> - AGENT_WITHDRAW_SELECTOR<br /> - AGENT_BORROW_SELECTOR<br /> - AGENT_REPAY_SELECTOR<br /> - AGENT_MINT_POWER_SELECTOR<br /> - AGENT_BURN_POWER_SELECTOR<br /> |
| **Agent** | ROLE_AGENT | - AUTH_SET_USER_ROLE_SELECTOR |





