// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {SignedCredential, VerifiableCredential, Credentials} from "src/Types/Structs/Credentials.sol";
import {
  ROUTE_AGENT_POLICE
} from "src/Constants/Routes.sol";
import {MinerHelper} from "helpers/MinerHelper.sol";

contract Agent is IAgent, RouterAware, Operatable {

  using Credentials for VerifiableCredential;
  using MinerHelper for uint64;

  error Unauthorized();
  error InsufficientFunds();
  error InsufficientCollateral();
  error Internal();
  error BadAgentState();
  /// @notice `id` is the GLIF Pools ID address of the Agent (not to be confused with the evm actor's ID address)
  uint256 public id;
  /// @notice `miners` Returns the minerID at a specific index
  uint64[] public miners;
  /// @notice `newAgent` returns an address of an upgraded agent during the upgrade process
  address public newAgent;
  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  /// @dev a modifier that protects function calls
  /// only owner, operator, or agent police can call
  modifier onlyAuthOrPolice {
    _onlyAuthOrPolice();
    _;
  }

  /// @dev a modifier that checks and immediately burns a signed credential
  modifier validateAndBurnCred(SignedCredential memory signedCredential) {
    _validateAndBurnCred(signedCredential);
    _;
  }

  modifier onlyAgentFactory() {
    AuthController.onlyAgentFactory(router, msg.sender);
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
   * @notice Returns the total number of miners pledged to this Agent
   */
  function minersCount() external view returns (uint256) {
    return miners.length;
  }

  /**
   * @notice Get the number of pools that an Agent is actively borrowing from
   * @return count Returns the number of pools that an Agent has staked power tokens in
   *
   * @dev this corresponds to the number of Pools that an Agent is actively borrowing from
   */
  function borrowedPoolsCount() public view returns (uint256 count) {
    count = _getStakedPoolIDs().length;
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
    return address(this).balance + GetRoute.wFIL(router).balanceOf(address(this));
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
   * @param sc The a signed credential with an `addMiner` action type
   * The `target` in the `sc` is the uint64 ID of the miner
   *
   * @dev under the hood this function calls `changeOwnerAddress` on the underlying Miner Actor to claim its ownership.
   * The underlying Miner Actor's nextPendingOwner _must_ be the address of this Agent or else this call will fail.
   *
   * This function can only be called by the Agent's owner or operator
   */
  function addMiner(
    SignedCredential memory sc
  ) external onlyOwnerOperator validateAndBurnCred(sc) {
    // Confirm the miner is valid and can be added
    if (!sc.vc.target.configuredForTakeover()) revert Unauthorized();
    // change the owner address
    sc.vc.target.changeOwnerAddress(address(this));
    // add the miner to the central registry, this call will fail if the miner is already registered
    GetRoute.minerRegistry(router).addMiner(sc.vc.target);
    // push the miner to the Agent's list of miners
    miners.push(sc.vc.target);
  }

  /**
   * @notice Removes a miner from the miner registry
   * @param newMinerOwner The address that will become the new owner of the miner
   * @param sc The signed credential of the agent attempting to remove the miner. The `target` will be the uint64 miner ID to remove and the `value` will be the value of assets that would be removed along with this particular miner.
   *
   *
   * If an Agent is not actively borrowing from any Pools, it can always remove its Miners
   TODO: Default
   */
  function removeMiner(
    address newMinerOwner,
    SignedCredential memory sc
  )
    external
    onlyOwner
    validateAndBurnCred(sc)
  {
    // Remove the miner from the central registry
    GetRoute.minerRegistry(router).removeMiner(sc.vc.target);
    // remove this miner from the Agent's list of miners
    _popMinerFromList(sc.vc.target);
    // revert the transaction if any of the pools reject the removal
    GetRoute.agentPolice(router).isAgentOverLeveraged(sc.vc);
    // change the owner address of the miner to the new miner owner
    sc.vc.target.changeOwnerAddress(newMinerOwner);
  }

  /**
   * @notice Gets called by the agent factory to begin the upgrade process to a new Agent
   * @param _newAgent The address of the new agent to which the miner will be migrated
   */
  function decommissionAgent(address _newAgent) public onlyAgentFactory {
    // if the newAgent is already set, we've already started teh migration
    if (newAgent != address(0)) revert BadAgentState();
    // if the newAgent has a mismatching ID, revert
    if(IAgent(_newAgent).id() != id) revert Unauthorized();
    // set the newAgent in storage, which marks the upgrade process as starting
    newAgent = _newAgent;
    // Withdraw all liquid funds from the Agent to the newAgent
    (bool success,) = _newAgent.call{value: liquidAssets()}("");
    if (!success) revert Internal();
  }

  /**
   * @notice Migrates a miner from the current agent to a new agent
   * This function is useful for upgrading an agent to a new version
   * @param newAgent The address of the new agent to which the miner will be migrated
   * @param miner The address of the miner to be migrated
   */
  function migrateMiner(address newAgent, uint64 miner) external onlyOwner {
    if (address(newAgent) != msg.sender) revert Unauthorized();
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

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  /**
   * @notice Allows an agent to withdraw balance to a recipient. Only callable by the Agent's Owner(s).
   * @param receiver The address to which the funds will be withdrawn
   * @param sc The signed credential of the user attempting to withdraw balance with a `withdraw` action type
   * @dev A credential must be passed when existing $FIL is borrowed in order to compute the max withdraw amount
   */
  function withdrawBalance(
    address receiver,
    SignedCredential memory sc
  ) external onlyOwner validateAndBurnCred(sc) {
    _poolFundsInFIL(sc.vc.value);

    (bool success,) = receiver.call{value: sc.vc.value}("");
    if (!success) revert Internal();

    // revert the transaction if any of the pools reject the removal
    GetRoute.agentPolice(router).isAgentOverLeveraged(sc.vc);

    emit WithdrawBalance(receiver, sc.vc.value);
  }

  /**
   * @notice Allows an agent to pull up funds from a staked Miner Actor into the Agent
   * @param sc The signed credential of the user attempting to pull funds from a miner. The credential must contain a `pullFundsFromMiner` action type with the `value` field set to the amount to pull, and the `target` as the ID of the miner to pull funds from
   * @dev The Agent must own the miner its withdrawing funds from
   *
   * This function adds a native FIL balance to the Agent
   */
  function pullFundsFromMiner(SignedCredential memory sc)
    external
    onlyAuthOrPolice
    validateAndBurnCred(sc)
  {
    // revert if this agent does not own the underlying miner
    _checkMinerRegistered(sc.vc.target);
    // pull up the funds from the miner
    sc.vc.target.withdrawBalance(sc.vc.value);
  }

  /**
   * @notice Allows an agent to push funds to a miner
   * @param sc The signed credential of the user attempting to push funds to a miner. The credential must contain a `pushFundsFromMiner` action type with the `value` field set to the amount to push, and the `target` as the ID of the miner to push funds to
   * @dev The Agent must own the miner its withdrawing funds from
   * If the agents FIL balance is less than the total amount to push, the function will attempt to convert any wFIL before reverting
   * TODO: this function cannot be called if the Agent is in default
   */
  function pushFundsToMiner(SignedCredential memory sc)
    external
    onlyOwnerOperator
    validateAndBurnCred(sc)
  {
    // revert if this agent does not own the underlying miner
    _checkMinerRegistered(sc.vc.target);
    // since built-in actors need FIL not WFIL, we unwrap as much WFIL as we need to push funds
    _poolFundsInFIL(sc.vc.value);
    // push the funds down
    sc.vc.target.transfer(sc.vc.value);
  }

  /**
   * @notice Allows an agent to borrow funds from a Pool
   * @param poolID The ID of the pool to borrow from
   * @param sc The signed credential of the user attempting to borrow funds from a pool. The credential must contain a `borrow` action type with the `value` field set to the amount to borrow. In case of a `borrow` action, the `target` field goes unused
   *
   * @dev The transaction will revert if the agent becomes overleveraged after borrowing
   */
  function borrow(
    uint256 poolID,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    /// notInDefault (check with police)
    validateAndBurnCred(sc)
  {
    IPool pool = GetRoute.pool(router, poolID);

    IAgentPolice police = GetRoute.agentPolice(router);
    // first time staking, add the poolID to the list of pools this agent is staking in
    if (pool.getAgentBorrowed(id) == 0) {
      if (borrowedPoolsCount() > police.maxPoolsPerAgent()) {
        revert BadAgentState();
      }
      police.addPoolToList(poolID);
    }

    pool.borrow(sc.vc);
    // transaction will revert if any of the pool's accounts reject the new agent's state
    police.isAgentOverLeveraged(sc.vc);
  }

  /**
   * @notice Allows an agent to repay funds to a Pool
   * @param poolID The ID of the pool to repay to
   * @param sc The signed credential of the user attempting to repay funds to a pool. The credential must contain a `repay` action type with the `value` field set to the amount to repay. In case of a `repay` action, the `target` field goes unused
   * @dev If the payment covers all the interest owed, then the remaining payments will go towards down principal
   *
   * The Agent's account must exist in order to pay back to a pool
   */
  function pay(
    uint256 poolID,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    validateAndBurnCred(sc)
    returns (uint256 rate, uint256 epochsPaid)
  {
    IPool pool = GetRoute.pool(router, poolID);
    GetRoute.wFIL(router).approve(address(pool), sc.vc.value);
    (rate, epochsPaid, ) = pool.pay(sc.vc);
  }

  /**
   * @notice Allows an agent to refinance their position from one pool to another
   * This is useful in situations where the Agent is illiquid in power and FIL,
   * and can secure a better rate from a different pool
   * @param oldPoolID The ID of the pool to exit from
   * @param newPoolID The ID of the pool to borrow from
   * @param sc The signed credential of the agent refinance the pool
   * @dev This function acts like one Pool "buying out" the position of an Agent on another Pool
   */
  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
    SignedCredential memory sc
  ) external onlyOwnerOperator validateAndBurnCred(sc) {}

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

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

  function _onlyAuthOrPolice() internal view {
    if (
      owner() != _msgSender() &&
      operator() != _msgSender() &&
      IRouter(router).getRoute(ROUTE_AGENT_POLICE) != msg.sender
    ) revert Unauthorized();
  }

  function _validateAndBurnCred(
    SignedCredential memory signedCredential
  ) internal {
    IAgentPolice agentPolice = GetRoute.agentPolice(router);
    agentPolice.isValidCredential(id, msg.sig, signedCredential);
    agentPolice.registerCredentialUseBlock(signedCredential);
  }

  function _getStakedPoolIDs() internal view returns (uint256[] memory) {
    return GetRoute.agentPolice(router).poolIDs(id);
  }

  function _getAccount(uint256 poolID) internal view returns (Account memory) {
    return IRouter(router).getAccount(id, poolID);
  }

  function _checkMinerRegistered(uint64 miner) internal view {
    if (!GetRoute.minerRegistry(router).minerRegistered(id, miner)) revert Unauthorized();
  }

  function _popMinerFromList(uint64 miner) internal {
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        miners[i] = miners[miners.length - 1];
        miners.pop();
        break;
      }
    }
  }
}
