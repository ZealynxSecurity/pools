// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AccountV2} from "./Account.sol";

library AccountHelpersV2 {
  using FixedPointMathLib for uint256;

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
  ) internal view returns (AccountV2 memory) {
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
  ) internal view returns (AccountV2 memory) {
    return IRouter(router).getAccount(agentID, poolID);
  }

  /**
   * @dev Returns true if an account exists
   */
  function exists(
    AccountV2 memory account
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
    AccountV2 memory account
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
    AccountV2 memory account
  ) internal {
    IRouter(router).setAccount(agentID, poolID, account);
  }

  /**
   * @dev Resets an account to default values
   *
   * in order to mutate the account, we have to manually reset all values,
   * instead of setting the account to be a new instance of an empty Account struct
   */
  function reset(AccountV2 memory account) internal pure {
    account.startEpoch = 0;
    account.principal = 0;
    account.epochsPaid = 0;
  }

  /*////////////////////////////////////////////////////////
                      Accounting
  ////////////////////////////////////////////////////////*/

  function borrow(
    AccountV2 memory account,
    IPoolImplementation poolImpl,
    uint256 borrowAmount,
    VerifiableCredential memory vc
  ) internal returns (uint256 borrowedAmount, uint256 rate) {
    // fresh account, set start epoch and epochsPaid to beginning of current window
    if (account.principal == 0) {
      uint256 currentEpoch = block.number;
      account.startEpoch = currentEpoch;
      account.epochsPaid = currentEpoch;
      borrowedAmount = borrowAmount;
    } else {
      // n + 1th borrow call
      uint256 rate = poolImpl.getRate(account);
    }

    account.principal += borrowedAmount;
  }

  function paymentsDue(
    AccountV2 memory account,
    VerifiableCredential memory vc,
    IPoolImplementation poolImpl
  ) internal view returns (uint256) {
    uint256 rate = poolImpl.getRate(0, account, vc);
    return
  }
}
