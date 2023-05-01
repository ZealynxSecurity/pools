// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {Credentials, SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {FilAddress} from "shim/FilAddress.sol";

/**
 * @title Agent
 * @author GLIF
 * @notice The Agent is a collateral and policy enforcement wrapper around one or more Filecoin Miner Actors. It is the primary interface for borrowing from the GLIF Pools Protocol.
 */
contract Agent is IAgent, Operatable {

  using MinerHelper for uint64;
  using FilAddress for address;
  using FilAddress for address payable;
  using Credentials for VerifiableCredential;

  error InsufficientFunds();
  error BadAgentState();

  address public immutable router;

  // cached routes to save on gas and code size
  IWFIL private wFIL;
  IAgentPolice private agentPolice;
  IMinerRegistry private minerRegistry;

  /// @notice `version` is the version of Agent that is deployed
  uint8 public immutable version;

  /// @notice `id` is the GLIF Pools ID address of the Agent (not to be confused with the evm actor's ID address)
  uint256 public immutable id;

  /// @notice `newAgent` returns an address of an upgraded agent during the upgrade process
  address public newAgent;

  /// @notice `administration` returns the address of an admin that can make payments on behalf of the agent, _only_ when the Agent falls behind on payments
  address public administration;
  
  /// @notice `publicKey` is a hashed key that the ado uses to validate requests from the agent
  address public adoRequestKey;

  /// @notice `faultySectorStartEpoch` is the epoch that one of the Agent's miners began having faulty sectors
  uint256 public faultySectorStartEpoch;

  /// @notice `defaulted` returns true if the agent is in default
  bool public defaulted;


  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  /// @dev we override the onlyOwnerOperator modifier to include the administration
  modifier onlyOwnerOperator() override {
    _onlyOwnerOperatorOverride();
    _;
  }

  /// @dev a modifier that checks and immediately burns a signed credential
  modifier validateAndBurnCred(SignedCredential memory signedCredential) {
    _validateAndBurnCred(signedCredential);
    _;
  }

  modifier onlyAgentPolice() {
    AuthController.onlyAgentPolice(router, msg.sender);
    _;
  }

  modifier notOnAdministration() {
    if (administration != address(0)) revert Unauthorized();
    _;
  }

  modifier notInDefault() {
    if (defaulted) revert BadAgentState();
    _;
  }

  modifier notPaused() {
    if (agentPolice.paused()) revert Unauthorized();
    _;
  }

  modifier checkVersion() {
    if (GetRoute.agentDeployer(router).version() != version) revert BadAgentState();
    _;
  }

  constructor(
    uint8 agentVersion,
    uint256 agentID,
    address agentRouter,
    address owner,
    address operator
  ) Operatable(owner, operator) {
    version = agentVersion;
    router = agentRouter;
    id = agentID;

    wFIL = GetRoute.wFIL(router);
    agentPolice = GetRoute.agentPolice(router);
    minerRegistry = GetRoute.minerRegistry(router);
  }

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  /**
   * @notice Get the number of pools that an Agent is actively borrowing from
   * @return count Returns the number of pools that an Agent has borrowed from
   */
  function borrowedPoolsCount() external view returns (uint256 count) {
    return GetRoute.poolRegistry(router).poolIDs(id).length;
  }

  /**
   * @notice Get the total liquid assets of the Agent, not including any liquid assets on any of its staked Miners
   * @return liquidAssets Returns the total liquid assets of the Agent in FIL and wFIL
   *
   * @dev once assets are flushed down into Miners, the liquidAssets will decrease, but the total liquidationValue of the Agent should not change
   */
  function liquidAssets() public view returns (uint256) {
    return address(this).balance + wFIL.balanceOf(address(this));
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
   * @notice Adds a miner id to the agent
   * @param sc The a signed credential with an `addMiner` action type. The `target` in the `sc` is the uint64 ID of the miner These credentials will not be issued for invalid miner IDs
   * @dev Under the hood this function calls `changeOwnerAddress` on the underlying Miner Actor to claim its ownership.
   * @dev The underlying Miner Actor's nextPendingOwner _must_ be the address of this Agent or else this call will fail.
   *
   * This function can only be called by the Agent's owner or operator
   */
  function addMiner(
    SignedCredential memory sc
  ) external onlyOwnerOperator validateAndBurnCred(sc) checkVersion {
    // confirm the miner is valid and can be added
    if (!sc.vc.target.configuredForTakeover()) revert Unauthorized();
    // change the owner address
    sc.vc.target.changeOwnerAddress(address(this));
    // add the miner to the central registry, this call will revert if the miner is already registered
    minerRegistry.addMiner(id, sc.vc.target);
  }

  /**
   * @notice Removes a miner from the Agent. The Agent must have sufficient equity in order to execute this action.
   * @param newMinerOwner The address that will become the new owner of the miner
   * @param sc The signed credential of the agent attempting to remove the miner. The `target` will be the uint64 miner ID to remove and the `value` will be the value of assets that would be removed along with this particular miner.
   * @dev Under the hood this function calls `changeOwnerAddress` on the underlying Miner Actor to propose an ownership claim. The new owner must then call `changeOwnerAddress` on the Miner Actor to claim ownership.
   * @dev The Agent must maintain a DTE < 1 in order to remove a miner.
   */
  function removeMiner(
    address newMinerOwner,
    SignedCredential memory sc
  )
    external
    onlyOwner
    checkVersion
    notPaused
    notOnAdministration
    notInDefault
    validateAndBurnCred(sc)
  {
    // checks to see if Agent has enough equity to remove miner
    agentPolice.confirmRmEquity(sc.vc);
    // remove the miner from the central registry
    minerRegistry.removeMiner(id, sc.vc.target);
    // change the owner address of the miner to the new miner owner
    sc.vc.target.changeOwnerAddress(newMinerOwner);
  }

  /**
   * @notice Gets called by the agent factory to begin the upgrade process to a new Agent
   * @param _newAgent The address of the new agent to which the miner will be migrated
   */
  function decommissionAgent(address _newAgent) external {
    // only the agent factory can decommission an agent
    AuthController.onlyAgentFactory(router, msg.sender);
    // if the newAgent has a mismatching ID, revert
    if(IAgent(_newAgent).id() != id) revert Unauthorized();
    // set the newAgent in storage, which marks the upgrade process as starting
    newAgent = _newAgent;
    uint256 _liquidAssets = liquidAssets();
    // Withdraw all liquid funds from the Agent to the newAgent
    _poolFundsInFIL(_liquidAssets);
    // transfer funds to new agent
    payable(_newAgent).sendValue(_liquidAssets);
  }

  /**
   * @notice Migrates a miner from the current agent to a new agent
   * This function is useful for upgrading an agent to a new version
   * @param miner The address of the miner to be migrated
   */
  function migrateMiner(uint64 miner) external {
    if (newAgent != msg.sender) revert Unauthorized();
    uint256 newId = IAgent(newAgent).id();
    if (
      // first check to make sure the agentFactory knows about this "agent"
      GetRoute.agentFactory(router).agents(newAgent) != newId ||
      // then make sure this is the same agent, just upgraded
      newId != id ||
      // check to ensure this miner was registered to the original agent
      !minerRegistry.minerRegistered(id, miner)
    ) revert Unauthorized();

    // propose an ownership change (must be accepted in v2 agent)
    miner.changeOwnerAddress(newAgent);

    emit MigrateMiner(msg.sender, newAgent, miner);
  }

  /**
   * @notice Prepares a miner for liquidation by changing its owner address
   * @param miner The ID of the miner to be liquidated
   * @param liquidator The address of the liquidator
   */
  function prepareMinerForLiquidation(uint64 miner, address liquidator) external onlyAgentPolice {
  if (!defaulted) revert Unauthorized();
    miner.changeOwnerAddress(liquidator);
  }

  /**
   * @notice `setFaulty` Marks the agent as having faulty sectors at a particular epoch
   * @dev Can be called multiple times on the same Agent without getting the wrong result
   */
  function setFaulty() external onlyAgentPolice {
    // dont reset faultySectorStartEpoch if one already exists
    if (faultySectorStartEpoch == 0) {
      faultySectorStartEpoch = block.number;
    }
  }

  /**
   * @notice `setRecovered` Marks the agent as having recovered from being in an administration state
   * @param sc The signed credential of the agent attempting to recover
   * @dev the `sc` must have under the tolerance ratio of faultySectors:liveSectors in order for this call to succeed
   * @dev the Account must be paid up within the defaultWindow in order for this call to succeed
   * @dev if the Agent has recovered, administration gets removed
   */
  function setRecovered(SignedCredential memory sc) 
    external
    onlyOwnerOperator
    validateAndBurnCred(sc)
    notPaused
    notInDefault
    checkVersion
  {
    agentPolice.confirmRmAdministration(sc.vc);
    faultySectorStartEpoch = 0;
    administration = address(0);

    emit OffAdministration();
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
  ) external checkVersion {
    if (
      msg.sender != owner() &&
      msg.sender != administration
    ) revert Unauthorized();

    miner.changeWorkerAddress(worker, controlAddresses);
    emit ChangeMinerWorker(miner, worker, controlAddresses);
  }

  /**
   * @notice Sets the Agent in default to prepare for a liquidation
   * @dev This process is irreversible
   */
  function setInDefault() external onlyAgentPolice {
    defaulted = true;
  }

  /**
   * @notice Sets the administration address
   * @param _administration The address of the administration
   * @dev This process is reversible - it is the first step towards getting the Agent back in good standing
   */
  function setAdministration(address _administration) external onlyAgentPolice {
    administration = _administration;
  }

  /**
   * @notice `refreshRoutes` allows any caller to update the cached routes in this contract from the router
   */
  function refreshRoutes() external {
    wFIL = GetRoute.wFIL(router);
    agentPolice = GetRoute.agentPolice(router);
    minerRegistry = GetRoute.minerRegistry(router);
  }

  /**
   * @notice `setAdoRequestKey` allows the owner or operator to update the ado requester key in storage
   * @param _newKey The new public key
   */
  function setAdoRequestKey(address _newKey) external onlyOwnerOperator {
    adoRequestKey = _newKey;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  /**
   * @notice Allows an agent to withdraw balance to a recipient. Agent must have sufficient equity to withdraw.
   * @param receiver The address to which the funds will be withdrawn
   * @param sc The signed credential of the user attempting to withdraw balance with a `withdraw` action type. The credential's `value` field is the amount to withdraw.
   * @dev If the agent is not approved by every pool, or cannot maintain a DTE < 1, it cannot withdraw.
   * @dev A credential must be passed when existing $FIL is borrowed in order to compute the max withdraw amount
   */
  function withdraw(
    address receiver,
    SignedCredential memory sc
  ) external
    onlyOwner
    notPaused
    notInDefault
    notOnAdministration
    checkVersion
    validateAndBurnCred(sc)
  {
    uint256 sendAmount = sc.vc.value;
    // Regardless of sender if the agent is overleveraged they cannot withdraw
    agentPolice.confirmRmEquity(sc.vc);
    // unwrap any wfil needed to withdraw
    _poolFundsInFIL(sendAmount);
    // transfer funds
    payable(receiver).sendValue(sendAmount);

    emit Withdraw(receiver, sendAmount);
  }

  /**
   * @notice Allows an agent to pull up funds from a pledged Miner Actor into the Agent
   * @param sc The signed credential of the Agent attempting to pull funds from a miner. The credential must contain a `pullFunds` action type with the `value` field set to the amount to pull, and the `target` as the ID of the miner to pull funds from
   * @dev The Agent must own the miner its withdrawing funds from
   *
   * This function adds a native FIL balance to the Agent
   */
  function pullFunds(SignedCredential memory sc)
    external
    onlyOwnerOperator
    validateAndBurnCred(sc)
    checkVersion
  {
    // revert if this agent does not own the underlying miner
    _checkMinerRegistered(sc.vc.target);
    // pull up the funds from the miner
    sc.vc.target.withdrawBalance(sc.vc.value);
  }

  /**
   * @notice Allows an agent to push funds to a miner
   * @param sc The signed credential of the Agent attempting to push funds to a miner. The credential must contain a `pushFunds` action type with the `value` field set to the amount to push, and the `target` as the ID of the miner to push funds to
   * If the agents FIL balance is less than the total amount to push, the function will attempt to convert any wFIL into FIL before reverting
   */
  function pushFunds(SignedCredential memory sc)
    external
    onlyOwnerOperator
    notPaused
    notOnAdministration
    notInDefault
    validateAndBurnCred(sc)
    checkVersion
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
   * @dev The transaction will revert if the agent is not approved
   */
  function borrow(
    uint256 poolID,
    SignedCredential memory sc
  ) external
    onlyOwner
    notPaused
    notInDefault
    validateAndBurnCred(sc)
    checkVersion
  {
    GetRoute.pool(router, poolID).borrow(sc.vc);
    // transaction will revert if any of the pool's accounts reject the new agent's state
    agentPolice.agentApproved(sc.vc);
  }

  /**
   * @notice Allows an agent to repay funds to a Pool
   * @param poolID The ID of the pool to repay to
   * @param sc The signed credential of the user attempting to repay funds to a pool. The credential must contain a `repay` action type with the `value` field set to the amount to repay. In case of a `repay` action, the `target` field goes unused
   * @dev If the payment covers all the interest owed, then the remaining payments will go towards down principal. If the amount exceeds both the interest and the principal, then the remaining amount will be refunded to the agent
   *
   * The Agent's account must exist in order to pay back to a pool
   */
  function pay(
    uint256 poolID,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    validateAndBurnCred(sc)
    checkVersion
    returns (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund)
  {
    // get the Pool address
    IPool pool = GetRoute.pool(router, poolID);
    // aggregate funds into WFIL to make a payment
    _poolFundsInWFIL(sc.vc.value);
    // approve the pool to pull in the WFIL asset
    wFIL.approve(address(pool), sc.vc.value);
    // make the payment
    return pool.pay(sc.vc);
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  /// @dev ensures theres enough native FIL bal in the agent to push funds to miners
  function _poolFundsInFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;

    if (filBal >= amount) {
      return;
    }

    if (filBal + wFIL.balanceOf(address(this)) < amount) revert InsufficientFunds();

    wFIL.withdraw(amount - filBal);
  }

  /// @dev ensures theres enough wFIL bal in the agent to make payments to pools
  function _poolFundsInWFIL(uint256 amount) internal {
    uint256 wFILBal = wFIL.balanceOf(address(this));

    if (wFILBal >= amount) {
      return;
    }

    if (address(this).balance + wFILBal < amount) revert InsufficientFunds();

    wFIL.deposit{value: amount - wFILBal}();
  }

  /// @dev validates the credential, and then registers its signature with the agent police so it can't be used again
  function _validateAndBurnCred(
    SignedCredential memory signedCredential
  ) internal {
    agentPolice.isValidCredential(id, msg.sig, signedCredential);
    agentPolice.registerCredentialUseBlock(signedCredential);
  }

  /// @dev ensures `miner` is registered to the agent
  function _checkMinerRegistered(uint64 miner) internal view {
    if (!minerRegistry.minerRegistered(id, miner)) revert Unauthorized();
  }

  /// @dev ensures the caller is the owner, operator, or the administration address
  function _onlyOwnerOperatorOverride() internal view {
    // only allow calls from the owner, operator, or administration address (if one is set)
    if (
      msg.sender != owner() &&
      msg.sender != operator() &&
      msg.sender != administration
    ) revert Unauthorized();
  }

}
