// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Authority} from "src/Auth/Auth.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IStats} from "src/Types/Interfaces/IStats.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IMockMiner} from "src/Types/Interfaces/IMockMiner.sol"; // TODO: remove this for Filecoin.sol
import {SignedCredential, VerifiableCredential, Credentials} from "src/Types/Structs/Credentials.sol";
import {
  ChangeWorkerAddressParams,
  ChangeMultiaddrsParams,
  ChangePeerIDParams
} from "src/Types/Structs/Filecoin.sol";

import {
  ROUTE_AGENT_FACTORY,
  ROUTE_POWER_TOKEN,
  ROUTE_POOL_FACTORY,
  ROUTE_MINER_REGISTRY,
  ROUTE_WFIL_TOKEN,
  ROUTE_AGENT_POLICE,
  ROUTE_CRED_PARSER
} from "src/Constants/Routes.sol";
import {Roles} from "src/Constants/Roles.sol";
import {
  OverPowered,
  OverLeveraged,
  InvalidParams,
  InDefault,
  InsufficientCollateral,
  TooManyPools
} from "src/Errors.sol";

contract Agent is IAgent, RouterAware {
  using Credentials for VerifiableCredential;
  uint256 public id;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth {
    _requiresAuth();
    _;
  }

  modifier requiresAuthOrPolice {
    _requiresAuthOrPolice();
    _;
  }

  modifier notOverPowered {
    _notOverPowered();
    _;
  }

  modifier notOverLeveraged {
    _notOverLeveraged();
    _;
  }

  modifier notInDefault {
    _notInDefault();
    _;
  }

  modifier isValidCredential(SignedCredential memory signedCredential) {
    _isValidCredential(address(this), signedCredential);
    _;
  }

  constructor(
    address _router,
    uint256 _agentID
  ) {
    router = _router;
    id = _agentID;
  }

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  /**
   * @notice Get the amount of power tokens staked by a specific pool
   * @param poolID The id of the pool to check
   * @return tokensStaked Returns the amount of power tokens staked by the pool
   */
  function powerTokensStaked(uint256 poolID) public view returns (uint256) {
    return AccountHelpers.getAccount(router, id, poolID).powerTokensStaked;
  }

  /**
   * @notice Check if a miner is registered in the miner registry under this Agent
   * @param miner The address of the miner to check for registration
   * @return hasMiner Returns true if the miner is registered, false otherwise
   */
  function hasMiner(address miner) public view returns (bool) {
    return GetRoute.minerRegistry(router).minerRegistered(id, miner);
  }

  /**
   * @notice Get the total amount of power tokens staked across all Pools by this Agent
   * @return tokensStaked Returns the total amount of power tokens staked across all Pools
   */
  function totalPowerTokensStaked() public view returns (uint256 tokensStaked) {
    uint256[] memory poolIDs = _getStakedPoolIDs();
    uint256 staked = 0;
    for (uint256 i = 0; i < poolIDs.length; i++) {
      staked += powerTokensStaked(poolIDs[i]);
    }

    return staked;
  }

  /**
   * @notice Get the number of pools that an Agent has staked power tokens in
   * @return count Returns the number of pools that an Agent has staked power tokens in
   *
   * @dev this corresponds to the number of Pools that an Agent is actively borrowing from
   */
  function stakedPoolsCount() public view returns (uint256) {
    return _getStakedPoolIDs().length;
  }

  /**
   * @notice Get the maximum amount that can be withdrawn by an agent
   * @param signedCredential The signed credential of the user attempting to withdraw
   * @return maxWithdrawAmount Returns the maximum amount that can be withdrawn
   */
  function maxWithdraw(SignedCredential memory signedCredential) external view returns (uint256) {
    address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    return _maxWithdraw(signedCredential.vc, credParser);
  }

  /**
   * @notice Get the total liquid assets of the Agent, not including any liquid assets on any of its staked Miners
   * @return liquidAssets Returns the total liquid assets of the Agent in FIL and wFIL
   *
   * @dev once assets are flushed down into Miners,
   * the liquidAssets will decrease,
   * but the total liquidationValue of the Agent should not change
   */
  function liquidAssets() public view returns (uint256) {
    uint256 filBal = address(this).balance;
    uint256 wfilBal = GetRoute.wFIL20(router).balanceOf(address(this));
    return filBal + wfilBal;
  }

  /*//////////////////////////////////////////////
            PAYABLE / FALLBACK FUNCTIONS
  //////////////////////////////////////////////*/

  receive() external payable {}

  fallback() external payable {}

  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  /**
   * @notice Adds miner addresses to the miner registry
   * @param miners The addresses of the miners to add
   *
   * @dev under the hood this function calls `changeOwnerAddress` on the underlying Miner Actor to claim its ownership.
   * The underlying Miner Actor's nextPendingOwner _must_ be the address of this Agent or else this call will fail.
   *
   * This function can only be called by the Agent's owner or operator
   */
  function addMiners(address[] calldata miners) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMiner(miners[i]);
    }
  }
  /**
   * @notice Removes a miner from the miner registry
   * @param newMinerOwner The address that will become the new owner of the miner
   * @param miner The address of the miner to remove
   * @param agentCred The signed credential of the agent attempting to remove the miner
   * @param minerCred A credential uniquely about the miner to be removed
   *
   * @dev under the hood this function:
   * - makes sure the Agent is not already overPowered or overLeveraged
   * - checks to make sure that removing the miner will not:
   *    - put the Agent into an overLeveraged state
   *    - put the Agent into an overPowered State
   *    - remove too many assets from the Agent,
   *        effectively putting it under the min collateral amount as determined by the Pools
   * - changes the owner of the miner to the new owner - the new owner will have to claim directly with the Miner Actor
   *
   * If an Agent is not actively borrowing from any Pools, it can always remove its Miners
   */
  function removeMiner(
    address newMinerOwner,
    address miner,
    SignedCredential memory agentCred,
    // a credential uniquely about the miner we wish to remove
    SignedCredential memory minerCred
  )
    external
    notOverPowered
    notOverLeveraged
    requiresAuth
    isValidCredential(agentCred)
  {
    // also validate the minerCred against the miner to remove
    _isValidCredential(miner, minerCred);
    _checkRemoveMiner(agentCred.vc, minerCred.vc);

    // set the miners owner to the new owner
    _changeMinerOwner(miner, newMinerOwner);

    // Remove the miner from the central registry
    GetRoute.minerRegistry(router).removeMiner(miner);
  }
  /**
   * @notice Migrates a miner from the current agent to a new agent
   * This function is useful for upgrading an agent to a new version
   * @param newAgent The address of the new agent to which the miner will be migrated
   * @param miner The address of the miner to be migrated
   */
  function migrateMiner(address newAgent, address miner) external requiresAuth {
    uint256 newId = IAgent(newAgent).id();
    // first check to make sure the agentFactory knows about this "agent"
    require(GetRoute.agentFactory(router).agents(newAgent) == newId);
    // then make sure this is the same agent, just upgraded
    require(newId == id, "Cannot migrate miner to a different agent");
    // check to ensure this miner was registered to the original agent
    require(GetRoute.minerRegistry(router).minerRegistered(id, miner), "Miner not registered");
    // propose an ownership change (must be accepted in v2 agent)
    _changeMinerOwner(miner, newAgent);

    emit MigrateMiner(msg.sender, newAgent, miner);
  }

  /**
   * @notice Changes the worker address associated with a miner
   * @param miner The address of the miner whose worker address will be changed
   * @param params The parameters for changing the worker address, including the new worker address and the new control addresses
   * @dev miner must be owned by this Agent in order for this call to execute
   */
  function changeMinerWorker(
    address miner,
    ChangeWorkerAddressParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_worker_address(miner, params);
    emit ChangeMinerWorker(miner, params.new_worker, params.new_control_addresses);
  }
  /**
   * @notice Changes the miner's multiaddress
   * @param miner The address of the miner whose multiaddress will be changed
   * @param params The parameters for changing the multiaddress
   * @dev miner must be owned by this Agent in order for this call to execute
   */
  function changeMultiaddrs(
    address miner,
    ChangeMultiaddrsParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_multiaddresses(miner, params);
    emit ChangeMultiaddrs(miner, params.new_multi_addrs);
  }
  /**
   * @notice Changes the miner's peerID
   * @param miner The address of the miner whose peerID will be changed
   * @param params The parameters for changing the peerID
   * @dev miner must be owned by this Agent in order for this call to execute
   */
  function changePeerID(
    address miner,
    ChangePeerIDParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_peer_id(miner, params);
    emit ChangePeerID(miner, params.new_id);
  }

  /*//////////////////////////////////////////////////
          AGENT OWNERSHIP / OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  /**
   * @notice Enables or disables the operator role for a specific address
   * @param operator The address of the operator whose role will be changed
   * @param enabled A boolean value that indicates whether the operator role should be enabled or disabled for this addr
   * @dev only the owner of the agent can call this function
   */
  function setOperatorRole(address operator, bool enabled) external requiresAuth {
    IMultiRolesAuthority(
      address(AuthController.getSubAuthority(router, address(this)))
    ).setUserRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR), enabled);

    emit SetOperatorRole(operator, enabled);
  }
  /**
   * @notice Enables or disables the owner role for a specific address
   * @param owner The address of the operator whose role will be changed
   * @param enabled A boolean value that indicates whether the owner role should be enabled or disabled for this addr
   * @dev only the owner of the agent can call this function
   */
  function setOwnerRole(address owner, bool enabled) external requiresAuth {
    IMultiRolesAuthority(
      address(AuthController.getSubAuthority(router, address(this)))
    ).setUserRole(owner, uint8(Roles.ROLE_AGENT_OWNER), enabled);

    emit SetOwnerRole(owner, enabled);
  }

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/
  /**
   * @notice Allows an agent to mint power tokens
   * @param amount The amount of power tokens to mint
   * @param signedCredential The signed credential of the agent attempting to mint power tokens
   */
  function mintPower(
    uint256 amount,
    SignedCredential memory signedCredential
  ) external notOverPowered requiresAuth isValidCredential(signedCredential) {
    IPowerToken powerToken = GetRoute.powerToken(router);
    // check
    require(
      signedCredential.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) >= powerToken.powerTokensMinted(id) + amount,
      "Cannot mint more power than the miner has"
    );
    // interact
    powerToken.mint(amount);
  }

  /**
   * @notice Allows an agent to burn power tokens
   * @param amount The amount of power tokens to burn
   * @param signedCredential The signed credential of the agent attempting to burn power tokens
   * @return amount The amount of power tokens burned
   */
  function burnPower(
    uint256 amount,
    SignedCredential memory signedCredential
  ) external requiresAuthOrPolice isValidCredential(signedCredential) returns (uint256) {
    IERC20 powerToken = GetRoute.powerToken20(router);
    // check
    require(amount <= powerToken.balanceOf(address(this)), "Agent: Cannot burn more power than the agent holds");
    // interact
    IPowerToken(address(powerToken)).burn(amount);

    return amount;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  /**
   * @notice Allows an agent to withdraw balance to a recipient. Only callable by the Agent's Owner(s)
   * @param receiver The address to which the funds will be withdrawn
   * @param amount The amount of balance to withdraw
   * @dev This function will fail if there are any power tokens staked in any Pools.
   * It's a permissionless withdrawal as long as nothing is borrowed
   */
  function withdrawBalance(address receiver, uint256 amount) external requiresAuth {
    require(totalPowerTokensStaked() == 0, "Cannot withdraw funds while power tokens are staked");

    _withdrawBalance(receiver, amount);
  }

  /**
   * @notice Allows an agent to withdraw balance to a recipient. Only callable by the Agent's Owner(s).
   * @param receiver The address to which the funds will be withdrawn
   * @param amount The amount of balance to withdraw
   * @param signedCredential The signed credential of the user attempting to withdraw balance
   * @dev A credential must be passed when existing $FIL is borrowed in order to compute the max withdraw amount
   */
  function withdrawBalance(
    address receiver,
    uint256 amount,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    uint256 maxWithdrawAmt = _maxWithdraw(signedCredential.vc, credParser);

    if (maxWithdrawAmt < amount) {
      revert InsufficientCollateral(
        address(this),
        msg.sender,
        amount,
        maxWithdrawAmt,
        msg.sig,
        "Attempted to draw down too much collateral"
      );
    }

    _withdrawBalance(receiver, amount);
  }

  /**
   * @notice Allows an agent to pull up funds from multiple staked Miner Actors into the Agent
   * @param miners An array of miner addresses to pull funds from
   * @param amounts An array of amounts to pull from each miner
   * @dev the amounts correspond to the miners array.
   * The Agent must own the miners its withdrawing funds from
   *
   * This function adds a native FIL balance to the Agent
   */
  function pullFundsFromMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external requiresAuthOrPolice {
    require(miners.length == amounts.length, "Miners and amounts must be same length");
    for (uint256 i = 0; i < miners.length; i++) {
      _pullFundsFromMiner(miners[i], amounts[i]);
    }

    emit PullFundsFromMiners(miners, amounts);
  }

  /**
   * @notice Allows an agent to push funds to multiple miners
   * @param miners The addresses of the miners to push funds to
   * @param amounts The amounts of funds to push to each miner
   * @dev the amounts correspond to the miners array
   * If the agents FIL balance is less than the total amount to push, the function will attempt to convert any wFIL before reverting
   * This function cannot be called if the Agent is overLeveraged
   */
  function pushFundsToMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external notOverLeveraged requiresAuth {
    require(miners.length == amounts.length, "Miners and amounts must be same length");

    uint256 total = 0;
    for (uint256 i = 0; i < miners.length; i++) {
      total += amounts[i];
    }

    _poolFundsInFIL(total);

    for (uint256 i = 0; i < miners.length; i++) {
      _pushFundsToMiner(miners[i], amounts[i]);
    }

    emit PushFundsToMiners(miners, amounts);
  }

  /**
   * @notice Allows an agent to borrow funds from a pool
   * @param amount The amount of funds to borrow. Must be less than the `ask` in the `signedCredential`
   * @param poolID The ID of the pool from which to borrow
   * @param signedCredential The signed credential of the agent borrowing funds
   * @param powerTokenAmount The amount of power tokens to stake as collateral
   * @dev Only Agents in good standing can borrow funds.
   *
   * Every time an Agent borrows, they get a new rate
   *
   * An Agent can only borrow from a limited number of Pools at one time
   */
  function borrow(
    uint256 amount,
    uint256 poolID,
    SignedCredential memory signedCredential,
    uint256 powerTokenAmount
  ) external
    notOverPowered
    notOverLeveraged
    notInDefault
    requiresAuth
    isValidCredential(signedCredential)
  {
    IPool pool = GetRoute.pool(router, poolID);

    // first time staking, add the poolID to the list of pools this agent is staking in
    if (pool.getAgentBorrowed(id) == 0) {
      if (stakedPoolsCount() > GetRoute.agentPolice(router).maxPoolsPerAgent()) {
        revert TooManyPools(id, "Agent: Too many pools");
      }
      GetRoute.agentPolice(router).addPoolToList(poolID);
    }

    pool.borrow(amount, signedCredential, powerTokenAmount);
  }

  /**
   * @notice Allows an agent to refinance their position from one pool to another
   * This is useful in situations where the Agent is illiquid in power and FIL,
   * and can secure a better rate from a different pool
   * @param oldPoolID The ID of the pool to exit from
   * @param newPoolID The ID of the pool to borrow from
   * @param additionalPowerTokens The additional power tokens to stake as collateral in the new Pool
   * @param signedCredential The signed credential of the agent refinance the pool
   * @dev This function acts like one Pool "buying out" the position of an Agent on another Pool
   */
  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
    uint256 additionalPowerTokens,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    Account memory account = AccountHelpers.getAccount(
      router,
      address(this),
      oldPoolID
    );
    IPowerToken powerToken = GetRoute.powerToken(router);
    IPool oldPool = GetRoute.pool(router, oldPoolID);
    IPool newPool = GetRoute.pool(router, newPoolID);
    uint256 powStaked = account.powerTokensStaked;
    uint256 currentDebt = account.totalBorrowed;
    // NOTE: Once we have permissionless Pools, we need to protect against re-entrancy in the pool borrow.
    powerToken.mint(powStaked);
    newPool.borrow(currentDebt, signedCredential, powStaked + additionalPowerTokens);
    require(oldPool.exitPool(address(this), signedCredential, currentDebt) == powStaked, "Refinance failed");
    powerToken.burn(powStaked);
  }

  /**
   * @notice Allows an agent to exit a pool and repay a portion of the borrowed funds, and recouping power tokens
   * @param poolID The ID of the pool to exit
   * @param assetAmount The amount of funds to repay
   * @param signedCredential The signed credential of the agent exiting the pool
   * @dev When an Agent exits a Pool, their payment rate does not change
   */
  function exit(
    uint256 poolID,
    uint256 assetAmount,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    // TODO: optimize with https://github.com/glif-confidential/pools/issues/148
    IPool pool = GetRoute.pool(router, poolID);
    uint256 borrowedAmount = pool.getAgentBorrowed(id);

    require(borrowedAmount >= assetAmount, "Cannot exit more than borrowed");

    pool.asset().approve(address(pool), assetAmount);
    pool.exitPool(address(this), signedCredential, assetAmount);

    if (borrowedAmount == assetAmount) {
      // remove poolID from list of pools this agent is staking in
      GetRoute.agentPolice(router).removePoolFromList(poolID);
    }
  }

  /**
   * @notice Allows an agent to make payments to multiple pools
   * @param _poolIDs The IDs of the pools to which payments will be made
   * @param _amounts The amounts of the payments to be made to each pool
   * @param _signedCredential The signed credential of the agent making the payments
   */
  function makePayments(
    uint256[] calldata _poolIDs,
    uint256[] calldata _amounts,
    SignedCredential memory _signedCredential
  ) external requiresAuthOrPolice isValidCredential(_signedCredential) {
    if (_poolIDs.length != _amounts.length) {
      revert InvalidParams(
        msg.sender,
        address(this),
        msg.sig,
        "Pool IDs and amounts must be same length"
      );
    }
    require(_poolIDs.length == _amounts.length, "Pool IDs and amounts must be same length");

    uint256 total = 0;

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      total += _amounts[i];
    }

    _poolFundsInWFIL(total);

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      IPool pool = GetRoute.pool(router, _poolIDs[i]);
      pool.asset().approve(address(pool), _amounts[i]);
      pool.makePayment(address(this), _amounts[i]);
    }
  }

  /**
   * @notice Allows an agent to stake power tokens in lieu of making payments (to multiple pools)
   * @param _poolIDs The IDs of the pools to which payments will be made
   * @param _amounts The amounts of the payments to be made to each pool
   * @param _powerTokenTokenAmounts The amounts of power tokens to stake for each pool
   * @param _signedCredential The signed credential of the agent making the payments
   * @dev This function essentially borrows more funds in order to make a payment
   * Pools do not have to support this, but they can if they'd like to
   * Every time an Agent stakes power tokens to make a payment, they get a new payment rate
   */
  function stakeToMakePayments(
    uint256[] calldata _poolIDs,
    uint256[] calldata _amounts,
    uint256[] calldata _powerTokenTokenAmounts,
    SignedCredential memory _signedCredential
  ) external requiresAuth isValidCredential(_signedCredential) {
    if (_poolIDs.length != _amounts.length || _poolIDs.length != _powerTokenTokenAmounts.length) {
      revert InvalidParams(
        msg.sender,
        address(this),
        msg.sig,
        "Pool IDs, amounts, and power token amounts must be same length"
      );
    }

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      GetRoute.pool(router, _poolIDs[i]).stakeToPay(
        _amounts[i], _signedCredential, _powerTokenTokenAmounts[i]
      );
    }
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  function _checkRemoveMiner(
    VerifiableCredential memory agentCred,
    VerifiableCredential memory minerCred
  ) internal view returns (bool) {
    address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    // if nothing is borrowed, can remove
    if (totalPowerTokensStaked() == 0) {
      return true;
    }

    uint256 maxWithdrawAmt = _maxWithdraw(agentCred, credParser);
    uint256 minerLiquidationValue = _liquidationValue(
      minerCred.getAssets(credParser),
      minerCred.getLiabilities(credParser),
      0
    );
    _canRemovePower(agentCred.getQAPower(credParser), minerCred.getQAPower(credParser));

    if (maxWithdrawAmt <= minerLiquidationValue) {
      revert InsufficientCollateral(
        address(this),
        msg.sender,
        minerLiquidationValue,
        maxWithdrawAmt,
        msg.sig,
        "Agent does not have enough collateral to remove Miner"
      );
    }

    return true;
  }

  function _canAddMiner(address miner) internal view returns (bool) {
    // check to make sure pending owner is address(this);
    require(IMockMiner(miner).next_owner(miner) == address(this), "Agent must be set as the nextOwner on the miner");
    // check to make sure no beneficiary address (or that we were set as the beneficiary address)
    require(IMockMiner(miner).get_beneficiary(miner) == address(0) || IMockMiner(miner).get_beneficiary(miner) == address(this));

    return true;
  }

  function _changeMinerOwner(address miner, address owner) internal {
    IMockMiner(miner).change_owner_address(miner, owner);
  }

  function _addMiner(address miner) internal {
    // Confirm the miner is valid and can be added
    require(_canAddMiner(miner), "Cannot add miner unless it is set as the nextOwner on the miner and no beneficiary address is set");

    _changeMinerOwner(miner, address(this));

    GetRoute.minerRegistry(router).addMiner(miner);
  }

  function _pullFundsFromMiner(address miner, uint256 amount) internal {
    require(
      IMinerRegistry(GetRoute.minerRegistry(router)).minerRegistered(id, miner),
      "Agent does not own miner"
    );

    uint256 withdrawAmount = amount;
    if (withdrawAmount == 0) {
      // withdraw all if amount is 0
      withdrawAmount = miner.balance;
    }

    IMockMiner(miner).withdrawBalance(withdrawAmount);
  }

  function _pushFundsToMiner(address miner, uint256 amount) internal {
    (bool success, ) = miner.call{value: amount}("");
    require(success, "Failed to send funds to miner");
  }

  // ensures theres enough native FIL bal in the agent to push funds to miners
  function _poolFundsInFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;
    IERC20 wFIL20 = GetRoute.wFIL20(router);
    uint256 wFILBal = wFIL20.balanceOf(address(this));

    if (filBal >= amount) {
      return;
    }

    require(filBal + wFILBal >= amount, "Not enough FIL or wFIL to push to miner");

    IWFIL(address(wFIL20)).withdraw(amount - filBal);
  }

  // ensures theres enough wFIL bal in the agent to make payments to pools
  function _poolFundsInWFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;
    IERC20 wFIL20 = GetRoute.wFIL20(router);
    uint256 wFILBal = wFIL20.balanceOf(address(this));

    if (wFILBal >= amount) {
      return;
    }

    require(filBal + wFILBal >= amount, "Not enough FIL or wFIL to push to miner");

    IWFIL(address(wFIL20)).deposit{value: amount - wFILBal}();
  }

  function _burnPower(uint256 amount) internal returns (uint256) {
    IERC20 powerToken = GetRoute.powerToken20(router);
    // check
    require(amount <= powerToken.balanceOf(address(this)), "Agent: Cannot burn more power than the agent holds");
    // interact
    IPowerToken(address(powerToken)).burn(amount);

    return amount;
  }

  function _canCall() internal view returns (bool) {
    return AuthController.canCallSubAuthority(router, address(this));
  }

  function _requiresAuth() internal view {
    require(_canCall(), "Agent: Not authorized");
  }

  function _requiresAuthOrPolice() internal view {
    require(_canCall() || IRouter(router).getRoute(ROUTE_AGENT_POLICE) == (msg.sender), "Agent: Not authorized");
  }

  function _notOverPowered() internal view {
    if (GetRoute.agentPolice(router).isOverPowered(id)) {
      revert OverPowered(id, "Agent: Cannot perform action while overpowered");
    }
  }

  function _notOverLeveraged() internal view {
    if (GetRoute.agentPolice(router).isOverLeveraged(id)) {
      revert OverLeveraged(id, "Agent: Cannot perform action while overleveraged");
    }
  }

  function _notInDefault() internal view {
    if (GetRoute.agentPolice(router).isInDefault(id)) {
      revert InDefault(id, "Agent: Cannot perform action while in default");
    }
  }

  function _isValidCredential(
    address agent,
    SignedCredential memory signedCredential
  ) internal view returns (bool) {
    return GetRoute.agentPolice(router).isValidCredential(agent, signedCredential);
  }

  // TODO: should we add any EDR for some number of days to this?
  // thinking no... because assets can include this amount server side to give us more flexibility and cheaper gas
  function _maxWithdraw(VerifiableCredential memory vc, address credParser) internal view returns (uint256) {
    uint256 liquid = liquidAssets();

    // if nothing is borrowed, you can withdraw everything
    if (totalPowerTokensStaked() == 0) {
      return liquid;
    }

    uint256 liquidationValue = _liquidationValue(vc.getAssets(credParser), vc.getLiabilities(credParser), liquid);
    uint256 minCollateral = _minCollateral(vc);

    if (liquidationValue > minCollateral) {
      // dont report a maxWithdraw that the Agent can't currently afford..
      return Math.min(liquidationValue - minCollateral, liquid);
    }

    return 0;
  }

  function _minCollateral(
    VerifiableCredential memory vc
  ) internal view returns (uint256 minCollateral) {
    uint256[] memory poolIDs = _getStakedPoolIDs();

    for (uint256 i = 0; i < poolIDs.length; ++i) {
      uint256 poolID = poolIDs[i];
      minCollateral += GetRoute
        .pool(router, poolID)
        .implementation()
        .minCollateral(
          IRouter(router).getAccount(id, poolID),
          vc
        );
    }
  }

  /// @notice ensure we don't remove too much power
  function _canRemovePower(uint256 totalPower, uint256 powerToRemove) internal view {
      // ensure that the power we're removing by removing a miner does not put us into an "overPowered" state
      if (totalPower < powerToRemove + GetRoute.powerToken(router).powerTokensMinted(id)) {
        revert InsufficientCollateral(
          address(this),
          msg.sender,
          powerToRemove,
          // TODO: here we should do totalPower - powMinted, but that could underflow..
          0,
          msg.sig,
          "Attempted to remove a miner with too much power"
        );
      }
  }

  function _getStakedPoolIDs() internal view returns (uint256[] memory) {
    return GetRoute.agentPolice(router).poolIDs(id);
  }

  function _liquidationValue(
    uint256 assets,
    uint256 liabilities,
    uint256 liquid
  ) internal pure returns (uint256) {
    uint256 recoverableAssets = assets + liquid;
    if (recoverableAssets < liabilities) {
      return 0;
    }
    return recoverableAssets - liabilities;
  }

  function _withdrawBalance(address receiver, uint256 amount) internal {
    _poolFundsInFIL(amount);

    (bool success,) = receiver.call{value: amount}("");
    require(success, "Withdrawal failed.");

    emit WithdrawBalance(receiver, amount);
  }
}

