// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {SignedCredential, VerifiableCredential, Credentials} from "src/Types/Structs/Credentials.sol";
import {AgentBeneficiary} from "src/Types/Structs/Beneficiary.sol";
import {
  ROUTE_AGENT_POLICE
} from "src/Constants/Routes.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {FilAddress} from "shim/FilAddress.sol";

contract Agent is IAgent, Operatable {

  using Credentials for VerifiableCredential;
  using MinerHelper for uint64;
  using FilAddress for address;
  using FilAddress for address payable;

  error InsufficientFunds();
  error InsufficientCollateral();
  error Internal();
  error BadAgentState();

  /// @notice `id` is the GLIF Pools ID address of the Agent (not to be confused with the evm actor's ID address)
  uint256 public id;

  /// @notice `newAgent` returns an address of an upgraded agent during the upgrade process
  address public newAgent;

  address public router;

  /// @notice `administration` returns the address of an admin that can make payments on behalf of the agent, _only_ when the Agent falls behind on payments
  address public administration;

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

  modifier onlyAgentFactory() {
    AuthController.onlyAgentFactory(router, msg.sender);
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

  function beneficiary() external view returns (AgentBeneficiary memory) {
    return GetRoute.agentPolice(router).agentBeneficiary(id);
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
    GetRoute.minerRegistry(router).addMiner(id, sc.vc.target);
  }

  /**
   * @notice Removes a miner from the miner registry
   * @param newMinerOwner The address that will become the new owner of the miner
   * @param sc The signed credential of the agent attempting to remove the miner. The `target` will be the uint64 miner ID to remove and the `value` will be the value of assets that would be removed along with this particular miner.
   */
  function removeMiner(
    address newMinerOwner,
    SignedCredential memory sc
  )
    external
    onlyOwner
    notOnAdministration
    notInDefault
    validateAndBurnCred(sc)
  {
    // Remove the miner from the central registry
    GetRoute.minerRegistry(router).removeMiner(id, sc.vc.target);
    // revert the transaction if any of the pools reject the removal
    GetRoute.agentPolice(router).agentApproved(sc.vc);
    // change the owner address of the miner to the new miner owner
    sc.vc.target.changeOwnerAddress(newMinerOwner);
  }

  /**
   * @notice Gets called by the agent factory to begin the upgrade process to a new Agent
   * @param _newAgent The address of the new agent to which the miner will be migrated
   */
  function decommissionAgent(address _newAgent) public onlyAgentFactory {
    // if the newAgent has a mismatching ID, revert
    if(IAgent(_newAgent).id() != id) revert Unauthorized();
    // set the newAgent in storage, which marks the upgrade process as starting
    newAgent = _newAgent;
    uint256 _liquidAssets = liquidAssets();
    // Withdraw all liquid funds from the Agent to the newAgent
    _poolFundsInFIL(_liquidAssets);
    (bool success,) = _newAgent.call{value: _liquidAssets}("");
    if (!success) revert Internal();
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
      !GetRoute.minerRegistry(router).minerRegistered(id, miner)
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
  ) external {
    if (
      msg.sender != owner() &&
      msg.sender != administration
    ) revert Unauthorized();

    miner.changeWorkerAddress(worker, controlAddresses);
    emit ChangeMinerWorker(miner, worker, controlAddresses);
  }

  function changeBeneficiary(
    address beneficiary,
    uint256 expiration,
    uint256 quota
  ) external onlyOwner {
    GetRoute.agentPolice(router).changeAgentBeneficiary(
      // the beneficiary address gets normalized in agent police to save on code size
      beneficiary,
      id,
      expiration,
      quota
    );
  }

  /**
   * @notice Sets the Agent in default to prepare for a liquidation
   *
   * This process is irreversible
   */
  function setInDefault() external onlyAgentPolice {
    defaulted = true;
  }

  /**
   * @notice Sets the administration address
   * @param _administration The address of the administration
   *
   * This process is reversible - it is the first step towards getting the Agent back in good standing
   */
  function setAdministration(address _administration) external onlyAgentPolice {
    administration = _administration;
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
  function withdraw(
    address receiver,
    SignedCredential memory sc
  ) external
    notInDefault
    notOnAdministration
    validateAndBurnCred(sc)
  {
    IAgentPolice agentPolice = GetRoute.agentPolice(router);
    uint256 sendAmount = sc.vc.value;
    // Regardless of sender if the agent is overleveraged they cannot withdraw
    agentPolice.agentApproved(sc.vc);
    if (
      agentPolice.isBeneficiaryActive(id)
    ) {
      // This call will revert if the sender is not owner/beneficiary
      // Otherwise it will return up the lesser of beneficiary quota or the credentialed amount
      sendAmount = agentPolice.beneficiaryWithdrawable(receiver, msg.sender, id, sendAmount);
    }
    else if (msg.sender != owner()) {
      revert Unauthorized();
    }

    // unwrap any wfil needed to withdraw
    _poolFundsInFIL(sendAmount);
    // transfer funds
    payable(receiver).sendValue(sendAmount);

    emit Withdraw(receiver, sendAmount);
  }

  /**
   * @notice Allows an agent to pull up funds from a staked Miner Actor into the Agent
   * @param sc The signed credential of the user attempting to pull funds from a miner. The credential must contain a `pullFundsFromMiner` action type with the `value` field set to the amount to pull, and the `target` as the ID of the miner to pull funds from
   * @dev The Agent must own the miner its withdrawing funds from
   *
   * This function adds a native FIL balance to the Agent
   */
  function pullFunds(SignedCredential memory sc)
    external
    onlyOwnerOperator
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
   */
  function pushFunds(SignedCredential memory sc)
    external
    onlyOwnerOperator
    notOnAdministration
    notInDefault
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
   * @dev The transaction will revert if the agent is in a bad state after borrowing
   */
  function borrow(
    uint256 poolID,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    notInDefault
    validateAndBurnCred(sc)
  {
    GetRoute.pool(router, poolID).borrow(sc.vc);
    // transaction will revert if any of the pool's accounts reject the new agent's state
    GetRoute.agentPolice(router).agentApproved(sc.vc);
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
    returns (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund)
  {
    // get the Pool address
    IPool pool = GetRoute.pool(router, poolID);
    // aggregate funds into WFIL to make a payment
    _poolFundsInWFIL(sc.vc.value);
    // approve the pool to pull in the WFIL asset
    GetRoute.wFIL(router).approve(address(GetRoute.pool(router, poolID)), sc.vc.value);
    // make the payment
    return pool.pay(sc.vc);
  }

  /**
   * @notice Allows an agent to refinance their position from one pool to another
   * This is useful in situations where the Agent is illiquid in power and FIL,
   * and can secure a better rate from a different pool
   * @param oldPoolID The ID of the pool to exit from
   * @param newPoolID The ID of the pool to borrow from
   * @param sc The signed credential of the agent refinance the pool
   * @dev This function acts like one Pool "buying out" the position of an Agent on another Pool
   *
   * The `value` in the `refinance` credential must be equal to the total amount of FIL owed to the old pool
   */
  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    notInDefault
    validateAndBurnCred(sc)
  {
    // borrow the amount of FIL owed to the old pool (including interest) from the new pool
    GetRoute.pool(router, newPoolID).borrow(sc.vc);

    IPool oldPool = GetRoute.pool(router, oldPoolID);
    // approve old Pool to take wFIL from this agent
    GetRoute.wFIL(router).approve(address(oldPool), sc.vc.value);
    // pay back the old pool principal + interest
    (,uint256 epochsPaid,,) = oldPool.pay(sc.vc);
    // ensure the account is closed on the old pool
    if (epochsPaid > 0) revert BadAgentState();
    // transaction will revert if any of the pool's accounts reject the new agent's state
    GetRoute.agentPolice(router).agentApproved(sc.vc);
  }

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

  function _onlyOwnerOperatorOverride() internal view {
    // only allow calls from the owner, operator, or administration address (if one is set)
    if (
      msg.sender != owner() &&
      msg.sender != operator() &&
      msg.sender != administration
    ) revert Unauthorized();
  }

}
