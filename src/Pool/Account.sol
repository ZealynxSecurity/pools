// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Account} from "src/Types/Structs/Account.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";

library AccountHelpers {

  /*////////////////////////////////////////////////////////
                        Agent Utils
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Converts agent address to its ID
   */
  function agentAddrToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  /*////////////////////////////////////////////////////////
                      Account Getters
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Gets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the address of the agent
   * @param poolID the pool ID
   */
  function getAccount(
    address router,
    address agent,
    uint256 poolID
  ) internal view returns (Account memory) {
    return getAccount(router, agentAddrToID(agent), poolID);
  }

  /**
   * @dev Gets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agentID the agent's ID
   * @param poolID the pool ID
   */
  function getAccount(
    address router,
    uint256 agentID,
    uint256 poolID
  ) internal view returns (Account memory) {
    return IRouter(router).getAccount(agentID, poolID);
  }

  /**
   * @dev Returns true if an account exists
   */
  function exists(
    Account memory account
  ) internal pure returns (bool) {
    return account.startEpoch != 0;
  }

  /*////////////////////////////////////////////////////////
                      Account Setters
  ////////////////////////////////////////////////////////*/

  /**
   * @dev Sets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the agent's address
   * @param poolID the pool ID
   */
  function setAccount(
    address router,
    address agent,
    uint256 poolID,
    Account memory account
  ) internal {
    setAccount(router, agentAddrToID(agent), poolID, account);
  }

  /**
   * @dev Sets account for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agentID the agent's ID
   * @param poolID the pool ID
   */
  function setAccount(
    address router,
    uint256 agentID,
    uint256 poolID,
    Account memory account
  ) internal {
    IRouter(router).setAccount(agentID, poolID, account);
  }

  /**
   * @dev Resets an account to default values
   *
   * in order to mutate the account, we have to manually reset all values,
   * instead of setting the account to be a new instance of an empty Account struct
   */
  function reset(Account memory account) internal pure {
    account.startEpoch = 0;
    account.principal = 0;
    account.epochsPaid = 0;
  }

  /**
   * @dev Saves an account in storage for an `agent` with respect to a specific `poolID`
   * @param router the address of the router
   * @param agent the agent's ID
   * @param poolID the pool ID
   */
  function save(
    Account memory account,
    address router,
    uint256 agent,
    uint256 poolID
  ) internal {
    setAccount(router, agent, poolID, account);
  }
}
