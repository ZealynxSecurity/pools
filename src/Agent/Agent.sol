// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {GetRoute} from "src/Router/GetRoute.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Operatable} from "src/Auth/Operatable.sol";
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
import {SignedCredential, VerifiableCredential, Credentials} from "src/Types/Structs/Credentials.sol";
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
  Unauthorized,
  InvalidPower,
  InsufficientFunds,
  InsufficientCollateral,
  InvalidParams,
  Internal,
  BadAgentState
} from "src/Agent/Errors.sol";
import {MinerHelper} from "helpers/MinerHelper.sol";

contract Agent is IAgent, RouterAware, Operatable {
  using Credentials for VerifiableCredential;
  using MinerHelper for uint64;
  uint256 public id;
  /**
   * @notice Returns the minerID at a specific index
   */
  uint64[] public miners;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

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

  modifier equalLengthArrays(uint256[] memory a, uint256[] memory b) {
    _equalLengthArrays(a, b);
    _;
  }

  modifier minersMatchAmounts(uint64[] memory miners, uint256[] memory amounts) {
    _minersMatchAmounts(miners, amounts);
    _;
  }

  constructor(
    address _router,
    uint256 _agentID,
    address _owner,
    address _operator
  ) Operatable(_owner, _operator) {
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
    return _getAccount(poolID).powerTokensStaked;
  }

  /**
   * @notice Check if a miner is registered in the miner registry under this Agent
   * @param miner The address of the miner to check for registration
   * @return hasMiner Returns true if the miner is registered, false otherwise
   */
  function hasMiner(uint64 miner) public view returns (bool) {
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
   * @notice Returns the total number of miners pledged to this Agent
   */
  function minersCount() external view returns (uint256) {
    return miners.length;
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
    return _maxWithdraw(
      signedCredential.vc,
      IRouter(router).getRoute(ROUTE_CRED_PARSER)
    );
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
  function addMiners(uint64[] calldata miners) external onlyOwnerOperator {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMiner(miners[i]);
    }
  }
  /**
   * @notice Removes a miner from the miner registry
   * @param newMinerOwner The address that will become the new owner of the miner
   * @param miner The address of the miner to remove. NOTE: this is a uint64 masked in an address type
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
    uint64 miner,
    SignedCredential memory agentCred,
    // a credential uniquely about the miner we wish to remove
    SignedCredential memory minerCred
  )
    external
    onlyOwner
    notOverPowered
    notOverLeveraged
    isValidCredential(agentCred)
  {
    // also validate the minerCred against the miner to remove
    // the miner needs to be encoded as an address type for compatibility with the vc
    _isValidCredential(address(uint160(miner)), minerCred);
    _checkRemoveMiner(agentCred.vc, minerCred.vc);

    miner.changeOwnerAddress(newMinerOwner);

    // remove this miner from the Agent's list of miners
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        miners[i] = miners[miners.length - 1];
        miners.pop();
        break;
      }
    }

    // Remove the miner from the central registry
    GetRoute.minerRegistry(router).removeMiner(miner);
  }
  /**
   * @notice Migrates a miner from the current agent to a new agent
   * This function is useful for upgrading an agent to a new version
   * @param newAgent The address of the new agent to which the miner will be migrated
   * @param miner The address of the miner to be migrated
   */
  function migrateMiner(address newAgent, uint64 miner) external onlyOwnerOperator {
    uint256 newId = IAgent(newAgent).id();
    if (
      // first check to make sure the agentFactory knows about this "agent"
      GetRoute.agentFactory(router).agents(newAgent) != newId ||
      // then make sure this is the same agent, just upgraded
      newId != id ||
      // check to ensure this miner was registered to the original agent
      !GetRoute.minerRegistry(router).minerRegistered(id, miner)
    ) revert Unauthorized();

    // propose an ownership change (must be accepted in v2 agent)
    miner.changeOwnerAddress(newAgent);

    emit MigrateMiner(msg.sender, newAgent, miner);
  }

  /**
   * @notice Changes the worker address associated with a miner
   * @param miner The address of the miner whose worker address will be changed
   * @param worker the worker address
   * @param controlAddresses the control addresses to set
   * @dev miner must be owned by this Agent in order for this call to execute
   */
  function changeMinerWorker(
    uint64 miner,
    uint64 worker,
    uint64[] calldata controlAddresses
  ) external onlyOwner {
    miner.changeWorkerAddress(worker, controlAddresses);
    emit ChangeMinerWorker(miner, worker, controlAddresses);
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
  ) external notOverPowered onlyOwnerOperator isValidCredential(signedCredential) {
    IPowerToken powerToken = GetRoute.powerToken(router);
    // check
    if (
      signedCredential.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) < powerToken.powerTokensMinted(id) + amount
    ) revert InvalidPower();

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
    IPowerToken powerToken = GetRoute.powerToken(router);
    // check
    if (amount > powerToken.balanceOf(address(this)))
      revert InvalidPower();
    // interact
    powerToken.burn(amount);

    return amount;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

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
  ) external onlyOwner isValidCredential(signedCredential) {
    address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    uint256 maxWithdrawAmt = _maxWithdraw(signedCredential.vc, credParser);

    if (maxWithdrawAmt < amount) {
      revert InsufficientCollateral();
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
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory signedCredential
  )
    external
    requiresAuthOrPolice
    isValidCredential(signedCredential)
    minersMatchAmounts(miners, amounts)
  {
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
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory signedCredential
  )
    external
    onlyOwnerOperator
    isValidCredential(signedCredential)
    notOverLeveraged
    minersMatchAmounts(miners, amounts)
  {
    uint256 total = 0;
    for (uint256 i = 0; i < miners.length; i++) {
      total += amounts[i];
    }

    _poolFundsInFIL(total);

    for (uint256 i = 0; i < miners.length; i++) {
      uint64 miner = miners[i];
      if (!hasMiner(miner)) revert Unauthorized();
      miner.transfer(amounts[i]);
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
    onlyOwnerOperator
    notOverPowered
    notOverLeveraged
    notInDefault
    isValidCredential(signedCredential)
  {
    IPool pool = GetRoute.pool(router, poolID);
    IAgentPolice police = GetRoute.agentPolice(router);
    // first time staking, add the poolID to the list of pools this agent is staking in
    if (pool.getAgentBorrowed(id) == 0) {
      if (stakedPoolsCount() > police.maxPoolsPerAgent()) {
        revert BadAgentState();
      }
      police.addPoolToList(poolID);
    }

    GetRoute.powerToken(router).approve(address(pool), powerTokenAmount);
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
  ) external onlyOwnerOperator isValidCredential(signedCredential) {
    Account memory account = _getAccount(
      oldPoolID
    );
    IPowerToken powerToken = GetRoute.powerToken(router);
    IPool oldPool = GetRoute.pool(router, oldPoolID);
    IPool newPool = GetRoute.pool(router, newPoolID);
    uint256 powStaked = account.powerTokensStaked;
    uint256 currentDebt = account.totalBorrowed;
    // NOTE: Once we have permissionless Pools, we need to protect against re-entrancy in the pool borrow.
    powerToken.mint(powStaked);
    powerToken.approve(address(newPool), powStaked + additionalPowerTokens);
    newPool.borrow(
      currentDebt,
      signedCredential,
      powStaked + additionalPowerTokens
    );

    oldPool.asset().approve(address(oldPool), currentDebt);
    if (
      oldPool.exitPool(
        address(this),
        signedCredential,
        currentDebt
      ) != powStaked
    ) revert Internal();

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
  ) external onlyOwnerOperator isValidCredential(signedCredential) {
    // TODO: optimize with https://github.com/glif-confidential/pools/issues/148
    IPool pool = GetRoute.pool(router, poolID);
    uint256 borrowedAmount = pool.getAgentBorrowed(id);

    if (borrowedAmount < assetAmount) revert InvalidParams();

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
  )
    external
    requiresAuthOrPolice
    isValidCredential(_signedCredential)
    equalLengthArrays(_poolIDs, _amounts)
  {
    uint256 total = 0;
    for (uint256 i = 0; i < _poolIDs.length; i++) {
      total += _amounts[i];
    }

    _poolFundsInWFIL(total);

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      uint256 amount = _amounts[i];
      IPool pool = GetRoute.pool(router, _poolIDs[i]);
      pool.asset().approve(address(pool), amount);
      pool.makePayment(address(this), amount);
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

    uint256 minerLiquidationValue = _liquidationValue(
      minerCred.getAssets(credParser),
      minerCred.getLiabilities(credParser),
      0
    );
    _canRemovePower(agentCred.getQAPower(credParser), minerCred.getQAPower(credParser));

    if (_maxWithdraw(agentCred, credParser) <= minerLiquidationValue) {
      revert InsufficientCollateral();
    }

    return true;
  }

  function _addMiner(uint64 miner) internal {
    // Confirm the miner is valid and can be added
    if (!miner.configuredForTakeover()) revert Unauthorized();

    // change the owner address
    miner.changeOwnerAddress(address(this));

    // add the miner to the agent's list of miners
    miners.push(miner);

    GetRoute.minerRegistry(router).addMiner(miner);
  }

  function _pullFundsFromMiner(uint64 miner, uint256 amount) internal {
    if (
      !IMinerRegistry(
        GetRoute.minerRegistry(router)
      ).minerRegistered(id, miner)
    ) revert Unauthorized();

    miner.withdrawBalance(
      amount > 0 ? amount : miner.balance()
    );
  }

  // ensures theres enough native FIL bal in the agent to push funds to miners
  function _poolFundsInFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;
    IWFIL wFIL = GetRoute.wFIL(router);

    if (filBal >= amount) {
      return;
    }

    if (filBal + wFIL.balanceOf(address(this)) < amount) revert InsufficientFunds();

    wFIL.withdraw(amount - filBal);
  }

  // ensures theres enough wFIL bal in the agent to make payments to pools
  function _poolFundsInWFIL(uint256 amount) internal {
    IWFIL wFIL = GetRoute.wFIL(router);
    uint256 wFILBal = wFIL.balanceOf(address(this));

    if (wFILBal >= amount) {
      return;
    }

    if (address(this).balance + wFILBal < amount) revert InsufficientFunds();

    wFIL.deposit{value: amount - wFILBal}();
  }

  function _burnPower(uint256 amount) internal returns (uint256) {
    IPowerToken powerToken = GetRoute.powerToken(router);
    // check
    if (amount > powerToken.balanceOf(address(this)))
      revert InvalidPower();

    // interact
    powerToken.burn(amount);

    return amount;
  }

  function _requiresAuthOrPolice() internal view {
    if (
      owner() != _msgSender() &&
      operator() != _msgSender() &&
      IRouter(router).getRoute(ROUTE_AGENT_POLICE) != msg.sender
    ) revert Unauthorized();
  }

  function _notOverPowered() internal view {
    if (GetRoute.agentPolice(router).isOverPowered(id))
      revert BadAgentState();
  }

  function _notOverLeveraged() internal view {
    if (GetRoute.agentPolice(router).isOverLeveraged(id))
      revert BadAgentState();
  }

  function _notInDefault() internal view {
    if (GetRoute.agentPolice(router).isInDefault(id))
      revert BadAgentState();
  }

  function _isValidCredential(
    address agent,
    SignedCredential memory signedCredential
  ) internal  {
    IAgentPolice agentPolice = GetRoute.agentPolice(router);
    agentPolice.isValidCredential(agent, signedCredential);
    agentPolice.registerCredentialUseBlock(signedCredential);
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
          _getAccount(poolID),
          vc
        );
    }
  }

  /// @notice ensure that the power we're removing by removing a miner does not put us into an "overPowered" state
  function _canRemovePower(uint256 totalPower, uint256 powerToRemove) internal view {
    if (totalPower < powerToRemove + GetRoute.powerToken(router).powerTokensMinted(id)) {
      revert InsufficientCollateral();
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
    if (!success) revert Internal();

    emit WithdrawBalance(receiver, amount);
  }

  function _getAccount(uint256 poolID) internal view returns (Account memory) {
    return IRouter(router).getAccount(id, poolID);
  }

  function _equalLengthArrays(uint256[] memory a, uint256[] memory b) internal pure {
    if (a.length != b.length) revert InvalidParams();
  }

  function _minersMatchAmounts(
    uint64[] memory miners,
    uint256[] memory amounts
  ) internal pure {
    if (miners.length != amounts.length) revert InvalidParams();
  }
}

