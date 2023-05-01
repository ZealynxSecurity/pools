// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {ICredentials} from "src/Types/Interfaces/ICredentials.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential, Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable {

  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;
  using FilAddress for address;

  error AgentStateRejected();

  uint256 constant WAD = 1e18;

  /// @notice `defaultLookback` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is in default
  uint256 public defaultWindow;

  /// @notice `maxPoolsPoerAgent`
  uint256 public maxPoolsPerAgent;

  /// @notice `maxDTE` is the maximum amount of principal to equity ratio before withdrawals are prohibited
  /// NOTE this is separate DTE for withdrawing than any DTE that the Infinity Pool relies on
  uint256 public maxDTE = 1e18;

  /// @notice `maxConsecutiveFaultEpochs` is the number of epochs of consecutive faults that are required in order to put an agent on administration or into default
  uint256 public maxConsecutiveFaultEpochs = 3 * EPOCHS_IN_DAY;

  /// @notice `sectorFaultyTolerancePercent` is the percentage of sectors that can be faulty before an agent is considered in a faulty state. 1e18 = 100%
  uint256 public sectorFaultyTolerancePercent = 1e15;

  /// @notice `paused` is a flag that determines whether the protocol is paused
  bool public paused = false;

  /// @notice `_credentialUseBlock` maps signature bytes to when a credential was used
  mapping(bytes32 => uint256) private _credentialUseBlock;

  constructor(
    string memory _name,
    string memory _version,
    uint256 _defaultWindow,
    address _owner,
    address _operator,
    address _router
  ) VCVerifier(_name, _version, _router) Operatable(_owner, _operator) {
    defaultWindow = _defaultWindow;
    maxPoolsPerAgent = 10;
  }

  modifier onlyAgent() {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  modifier onlyWhenBehindTargetEpoch(address agent) {
    if (!_epochsPaidBehindTarget(IAgent(agent).id(), defaultWindow)) {
      revert Unauthorized();
    }
    _;
  }

  modifier onlyWhenConsecutiveFaultyEpochsExceeded(address agent) {
    if (!_consecutiveFaultyEpochsExceeded(agent)) {
      revert Unauthorized();
    }
    _;
  }

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  /**
   * @notice `agentApproved` checks with each pool to see if the agent's position is approved and reverts if any pool returns false
   * @param vc the VerifiableCredential of the agent
   */
  function agentApproved(
    VerifiableCredential calldata vc
  ) external view {
    _agentApproved(vc);
  }

  /**
   * @notice `setAgentDefaulted` puts the agent in default permanently
   * @param agent The address of the agent to put in default
   */
  function setAgentDefaulted(address agent) external onlyOwner onlyWhenBehindTargetEpoch(agent) {
    IAgent(agent).setInDefault();
    emit Defaulted(agent);
  }

  /**
   * @notice `agentLiquidated` checks if the agent has been liquidated
   * @param agentID The address of the agent to check
   */
  function agentLiquidated(uint256 agentID) public view returns (bool) {
    uint256[] memory pools = GetRoute.poolRegistry(router).poolIDs(agentID);

    if (pools.length == 0) return false;
    // once an Agent gets liquidated, all of their pools get written down, and accounts `defaulted` flag set to true
    // we only need to check the Agent's account in the first pool to see if the agent has been liquidated
    return (AccountHelpers.getAccount(router, agentID, pools[0]).defaulted);
  }

  /**
   * @notice `putAgentOnAdministration` puts the agent on administration, hopefully only temporarily
   * @param agent The address of the agent to put on administration
   * @param administration The address of the administration
   */
  function putAgentOnAdministration(
    address agent,
    address administration
  ) external
    onlyOwner
    onlyWhenBehindTargetEpoch(agent)
  {
    IAgent(agent).setAdministration(administration.normalize());
    emit OnAdministration(agent);
  }

  /**
   * @notice `markAsFaulty` marks the epoch height where one of an agent's miners began faulting
   * @param agents The IDs of the agents to mark as having faulty sectors
   */
  function markAsFaulty(IAgent[] calldata agents) external onlyOwnerOperator {
    IAgent agent;
    for (uint256 i = 0; i < agents.length; i++) {
      agent = agents[i];
      agent.setFaulty();
      emit FaultySectors(address(agent), block.number);
    }
  }

  /**
   * @notice `putAgentOnAdminstration` puts the agent on administration due to administrationFaultDays of consectutive faulty sector days
   */
  function putAgentOnAdministrationDueToFaultySectorDays(
    address agent,
    address administration
  ) external
    onlyOwner
    onlyWhenConsecutiveFaultyEpochsExceeded(agent)
  {
    IAgent(agent).setAdministration(administration.normalize());
    emit OnAdministration(agent);
  }

  /**
   * @notice `setAgentDefaultDueToFaultySectorDays` puts the agent on administration due to administrationFaultDays of consectutive faulty sector days
   */
  function setAgentDefaultDueToFaultySectorDays(
    address agent
  ) external
    onlyOwner
    onlyWhenConsecutiveFaultyEpochsExceeded(agent)
  {
    IAgent(agent).setInDefault();
    emit Defaulted(agent);
  }

  /**
   * @notice `prepareMinerForLiquidation` changes the owner address of `miner` on `agent` to be `owner` of Agent Police
   * @param agent The address of the agent to set the state of
   * @param miner The ID of the miner to change owner to liquidator
   * @dev After calling this function and the liquidation completes, call `liquidatedAgent` next to proceed with the liquidation
   */
  function prepareMinerForLiquidation(
    address agent,
    uint64 miner
  ) external onlyOwner {
    IAgent(agent).prepareMinerForLiquidation(miner, owner);
  }

  /**
   * @notice `distributeLiquidatedFunds` distributes liquidated funds to the pools
   * @param agent The address of the agent to set the state of
   * @param amount The amount of funds recovered from the liquidation
   */
  function distributeLiquidatedFunds(address agent, uint256 amount) external onlyOwner {
    uint256 agentID = IAgent(agent).id();
    // this call can only be called once per agent
    if (agentLiquidated(agentID)) revert Unauthorized();
    // transfer the assets into the pool
    GetRoute.wFIL(router).transferFrom(msg.sender, address(this), amount);
    uint256 excessAmount = _writeOffPools(agentID, amount);

    // transfer the excess assets to the Agent's owner
    GetRoute.wFIL(router).transfer(IAuth(agent).owner(), excessAmount);
  }

  /**
   * @notice `isValidCredential` returns true if the credential is valid
   * @param agent the ID of the agent
   * @param action the 4 byte function signature of the function the Agent is aiming to execute
   * @param sc the signed credential of the agent
   * @dev a credential is valid if it meets the following criteria:
   *      1. the credential is signed by the known issuer
   *      2. the credential is not expired
   *      3. the credential has not been used before
   *      4. the credential's `subject` is the `agent`
   */
  function isValidCredential(
    uint256 agent,
    bytes4 action,
    SignedCredential calldata sc
  ) external view {
    // reverts if the credential isn't valid
    validateCred(
      agent,
      action,
      sc
    );

    // check to see if this credential has been used for
    if (credentialUsed(sc.v, sc.r, sc.s)) revert InvalidCredential();
  }

  /**
   * @notice `credentialUsed` returns true if the credential has been used before
   */
  function credentialUsed(uint8 v, bytes32 r, bytes32 s) public view returns (bool) {
    return _credentialUseBlock[createSigKey(v, r, s)] > 0;
  }

  /**
   * @notice registerCredentialUseBlock burns a credential by storing a hash of its signature
   * @dev only an Agent can burn its own credential
   */
  function registerCredentialUseBlock(
    SignedCredential memory sc
  ) external {
    if (IAgent(msg.sender).id() != sc.vc.subject) revert Unauthorized();
    _credentialUseBlock[createSigKey(sc.v, sc.r, sc.s)] = block.number;
  }

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  /**
   * @notice `confirmRmEquity` checks to see if a withdrawal will bring the agent over maxDTE
   * @param vc the verifiable credential
   */
  function confirmRmEquity(
    VerifiableCredential calldata vc
  ) external view {
    // check to ensure we can withdraw from this pool
    _agentApproved(vc);
    // check to ensure the withdrawal does not bring us over maxDTE
    address credParser = address(GetRoute.credParser(router));
    // check to make sure the after the withdrawal, the DTE is under max
    uint256 principal = vc.getPrincipal(credParser);
    // nothing borrowed, so DTE is 0, good to go!
    if (principal == 0) return;

    uint256 agentTotalValue = vc.getAgentValue(credParser);
    // since agentTotalValue includes borrowed funds (principal),
    // agentTotalValue should always be greater than principal
    // however, this could happen if the agent is severely slashed over long durations
    // in this case, they're definitely over the maxDTE, regardless of what it's set to
    if (agentTotalValue <= principal) {
      revert AgentStateRejected();
    }

    // if the DTE is greater than maxDTE, revert
    if ((principal * WAD) / (agentTotalValue - principal) > maxDTE) {
      revert AgentStateRejected();
    }
  }

  /**
   * @notice `confirmRmAdministration` checks to ensure an Agent's faulty sectors are in the tolerance range, and they're within the payment tolerance window
   * @param vc the verifiable credential
   */
  function confirmRmAdministration(VerifiableCredential calldata vc) external view {
    address credParser = address(GetRoute.credParser(router));

    if (
      vc.getFaultySectors(credParser).divWadDown(vc.getLiveSectors(credParser)) > sectorFaultyTolerancePercent
    ) revert AgentStateRejected();

    if (_epochsPaidBehindTarget(vc.subject, defaultWindow)) revert AgentStateRejected();
  }

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  /**
   * @notice `setDefaultWindow` changes the default window epochs
   */
  function setDefaultWindow(uint256 _defaultWindow) external onlyOwner {
    defaultWindow = _defaultWindow;
  }

  /**
   * @notice `setMaxPoolsPerAgent` changes the maximum number of pools an agent can borrow from
   */
  function setMaxPoolsPerAgent(uint256 _maxPoolsPerAgent) external onlyOwner {
    maxPoolsPerAgent = _maxPoolsPerAgent;
  }

  /**
   * @notice `setMaxDTE` sets the maximum DTE for withdrawals and removing miners
   */
  function setMaxDTE(uint256 _maxDTE) external onlyOwner {
    maxDTE = _maxDTE;
  }

  /**
   * @notice `pause` sets this contract paused
   */
  function pause() external onlyOwner {
    paused = true;
  }

  /**
   * @notice `resume` resumes this contract
   */
  function resume() external onlyOwner {
    paused = false;
  }

  /**
   * @notice `setMaxConsecutiveFaultEpochs` sets the number of consecutive days of fault before the agent is put on administration or into default
   */
  function setMaxConsecutiveFaultEpochs(uint256 _maxConsecutiveFaultEpochs) external onlyOwner {
    maxConsecutiveFaultEpochs = _maxConsecutiveFaultEpochs;
  }

  /**
   * @notice `setSectorFaultyTolerancePercent` sets the percentage of sectors that can be faulty before the agent is considered faulty
   */
  function setSectorFaultyTolerancePercent(uint256 _sectorFaultyTolerancePercent) external onlyOwner {
    sectorFaultyTolerancePercent = _sectorFaultyTolerancePercent;
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  /// @dev computes the pro-rata split of a total amount based on principal
  function _writeOffPools(
    uint256 _agentID,
    uint256 _totalAmount
  ) internal returns (uint256 excessFunds) {
    // Setup the variables we use in the loops here to save gas
    uint256 totalPrincipal;
    uint256 i;
    uint256 poolID;
    uint256 poolShare;
    uint256 principal;
    IWFIL wFIL = GetRoute.wFIL(router);

    uint256[] memory _pools = GetRoute.poolRegistry(router).poolIDs(_agentID);
    uint256 poolCount = _pools.length;
    uint256 totalOwed;

    uint256[] memory principalAmts = new uint256[](poolCount);
    // add up total principal across pools, and cache the principal in each pool
    for (i = 0; i < poolCount; ++i) {
      principal = AccountHelpers.getAccount(router, _agentID, _pools[i]).principal;
      principalAmts[i] = principal;
      totalPrincipal += principal;
    }

    for (i = 0; i < poolCount; ++i) {
      poolID = _pools[i];
      // compute this pool's share of the total amount
      poolShare = (principalAmts[i] * _totalAmount / totalPrincipal);
      // approve the pool to pull in WFIL
      IPool pool = GetRoute.pool(router, poolID);
      wFIL.approve(address(pool), poolShare);
      // write off the pool's assets
      totalOwed = pool.writeOff(_agentID, poolShare);
      excessFunds += poolShare > totalOwed ? poolShare - totalOwed : 0;
    }
  }

  /// @dev returns true if any pool has an `epochsPaid` behind `targetEpoch` (and thus is underpaid)
  function _epochsPaidBehindTarget(
    uint256 _agentID,
    uint256 _targetEpoch
  ) internal view returns (bool) {
    uint256[] memory pools = GetRoute.poolRegistry(router).poolIDs(_agentID);

    for (uint256 i = 0; i < pools.length; ++i) {
      if (AccountHelpers.getAccount(router, _agentID, pools[i]).epochsPaid < block.number - _targetEpoch) {
        return true;
      }
    }

    return false;
  }

  /// @dev returns true if the Agent has 
  function _consecutiveFaultyEpochsExceeded(address _agent) internal view returns (bool) {
    uint256 faultyStart = IAgent(_agent).faultySectorStartEpoch();
    // if the agent is not faulty, return false
    if (faultyStart == 0) return false;

    // must be faulty for maxConsecutiveFaultEpochs epochs before taking action
    return block.number >= faultyStart + maxConsecutiveFaultEpochs;
  }

  /// @dev loops through the pools and calls isApproved on each, reverting in the case of any non-approvals
  function _agentApproved(VerifiableCredential calldata vc) internal view {
    uint256[] memory pools = GetRoute.poolRegistry(router).poolIDs(vc.subject);

    for (uint256 i = 0; i < pools.length; ++i) {
      uint256 poolID = pools[i];
      IPool pool = GetRoute.pool(router, poolID);
      if (!pool.isApproved(
        AccountHelpers.getAccount(router, vc.subject, poolID),
        vc
      )) {
        revert AgentStateRejected();
      }
    }
  }

  function createKey(string calldata partitionKey, uint256 agentID) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, agentID));
  }

  function createSigKey(uint8 v, bytes32 r, bytes32 s) internal pure returns (bytes32){
    return keccak256(abi.encode(v, r, s));
  }
}
