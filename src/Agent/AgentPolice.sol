// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Ownable} from "src/Auth/Ownable.sol";
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
import {Window} from "src/Types/Structs/Window.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {BeneficiaryHelpers, AgentBeneficiary} from "src/Types/Structs/Beneficiary.sol";
import {Roles} from "src/Constants/Roles.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
uint256 constant wad = 1e18;
contract AgentPolice is IAgentPolice, VCVerifier, Ownable {

  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;
  using FilAddress for address;
  using BeneficiaryHelpers for AgentBeneficiary;

  error AgentStateRejected();

  uint256 constant WAD = 1e18;

  /// @notice `defaultLookback` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is in default
  uint256 public defaultWindow;

  /// @notice `maxPoolsPoerAgent`
  uint256 public maxPoolsPerAgent;

  /// @notice `maxDTE` is the maximum amount of principal to equity ratio before withdrawals are prohibited
  /// NOTE this is separate DTE for withdrawing than any DTE that the Infinity Pool relies on
  uint256 public maxDTE = 1e18;

  /// @notice `paused` is a flag that determines whether the protocol is paused
  bool public paused = false;

  /// @notice `_liquidated` maps agentID to whether the liquidation process has been completed
  mapping(uint256 => bool) public liquidated;

  /// @notice `_poolIDs` maps agentID to the pools they have actively borrowed from
  mapping(uint256 => uint256[]) private _poolIDs;

  /// @notice `_credentialUseBlock` maps signature bytes to when a credential was used
  mapping(bytes32 => uint256) private _credentialUseBlock;

  /// @notice `_agentBeneficiaries` maps an Agent ID to its Beneficiary struct
  mapping(uint256 => AgentBeneficiary) private _agentBeneficiaries;

  constructor(
    string memory _name,
    string memory _version,
    uint256 _defaultWindow,
    address _owner,
    address _router
  ) VCVerifier(_name, _version, _router) Ownable(_owner) {
    defaultWindow = _defaultWindow;
    maxPoolsPerAgent = 10;
  }

  modifier onlyAgent() {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  // ensures that only the pool can change its own state in the agent police
  modifier onlyPool(uint256 poolID) {
    if (address(GetRoute.pool(router, poolID)) != msg.sender) {
      revert Unauthorized();
    }
    _;
  }

  modifier onlyWhenBehindTargetEpoch(address agent) {
    if (!_epochsPaidBehindTarget(IAgent(agent).id(), defaultWindow)) {
      revert Unauthorized();
    }
    _;
  }

  /*//////////////////////////////////////////////
                      GETTERS
  //////////////////////////////////////////////*/

  /**
   * @notice `poolIDs` returns the poolIDs of the pools that the agent has borrowed from
   * @param agentID the agentID of the agent
   */
  function poolIDs(uint256 agentID) external view returns (uint256[] memory) {
    return _poolIDs[agentID];
  }

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  /**
   * @notice `agentApproved` checks with each pool to see if the agent's position is approved and reverts if any pool returns false
   * @param vc the VerifiableCredential of the agent
   */
  function agentApproved(
    VerifiableCredential memory vc
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
   * @notice `rmAgentFromAdministration` removes the agent from administration
   * @param agent The address of the agent to remove from administration
   */
  function rmAgentFromAdministration(address agent) external onlyOwner {
    if (_epochsPaidBehindTarget(IAgent(agent).id(), defaultWindow)) revert Unauthorized();

    IAgent(agent).setAdministration(address(0));
    emit OffAdministration(agent);
  }

  /**
   * @notice `prepareMinerForLiquidation` changes the owner address of `miner` on `agent` to be `liquidator`
   * @param agent The address of the agent to set the state of
   * @param liquidator The address of the liquidator
   * @param miner The ID of the miner to change owner to liquidator
   * @dev After calling this function and the liquidation completes, call `liquidatedAgent` next to proceed with the liquidation
   */
  function prepareMinerForLiquidation(
    address agent,
    address liquidator,
    uint64 miner
  ) external onlyOwner {
    IAgent(agent).prepareMinerForLiquidation(miner, liquidator.normalize());
  }

  /**
   * @notice `liquidatedAgent` permanently sets the agent as liquidated in storage
   * @param agent The address of the agent to set the state of
   */
  function liquidatedAgent(address agent) external onlyOwner {
    if (!IAgent(agent).defaulted()) revert Unauthorized();

    liquidated[IAgent(agent).id()] = true;
  }

  /**
   * @notice `distributeLiquidatedFunds` distributes liquidated funds to the pools
   * @param agentID The ID of the agent to set the state of
   * @param amount The amount of funds recovered from the liquidation
   */
  function distributeLiquidatedFunds(uint256 agentID, uint256 amount) external {
    if (!liquidated[agentID]) revert Unauthorized();

    // transfer the assets into the pool
    GetRoute.wFIL(router).transferFrom(msg.sender, address(this), amount);
    _writeOffPools(agentID, amount);
  }

  /**
   * @notice `isValidCredential` returns true if the credential is valid
   * @param agent the ID of the agent
   * @param action the 4 byte function signature of the function the Agent is aiming to execute
   * @param signedCredential the signed credential of the agent
   * @dev a credential is valid if it meets the following criteria:
   *      1. the credential is signed by the known issuer
   *      2. the credential is not expired
   *      3. the credential has not been used before
   *      4. the credential's `subject` is the `agent`
   */
  function isValidCredential(
    uint256 agent,
    bytes4 action,
    SignedCredential memory signedCredential
  ) external view {
    // reverts if the credential isn't valid
    validateCred(
      agent,
      action,
      signedCredential
    );

    // check to see if this credential has been used for
    if (
      _credentialUseBlock[
        // hash the signature
        keccak256(abi.encode(
          signedCredential.v, signedCredential.r, signedCredential.s
        ))
      ] > 0
    ) revert InvalidCredential();
  }

  /// @dev burns a credential by storing a hash of its signature
  function registerCredentialUseBlock(SignedCredential memory signedCredential) external {
    _credentialUseBlock[keccak256(abi.encode(signedCredential.v, signedCredential.r, signedCredential.s))] = block.number;
  }

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  /**
   * @notice `addPoolToList` adds a pool to an agent's list of pools its borrowed from
   * @param pool the id of the pool to add
   * @dev only an agent can add a pool to its list
   * The agent itself ensures the pool is not a duplicate before calling this function
   */
  function addPoolToList(uint256 agentID, uint256 pool) external onlyPool(pool) {
    _poolIDs[agentID].push(pool);
  }

  /**
   * @notice `removePoolFromList` removes a pool from an agent's list of pools its borrowed from
   * @param pool the id of the pool to add
   * @dev only an agent can add a pool to its list
   */
  function removePoolFromList(uint256 agentID, uint256 pool) external onlyPool(pool) {
    uint256[] storage pools = _poolIDs[agentID];
    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == pool) {
        pools[i] = pools[pools.length - 1];
        pools.pop();
        break;
      }
    }
  }

  /*//////////////////////////////////////////////
                  BENEFICIARIES
  //////////////////////////////////////////////*/

  /**
   * @notice `isBeneficiaryActive` returns true if the beneficiary is active
   * @param agentID the ID of the agent
   */
  function isBeneficiaryActive(uint256 agentID) external view returns (bool) {
    return _agentBeneficiaries[agentID].isActive();
  }

  /**
   * @notice `agentBeneficiary` returns the beneficiary of an agent
   * @param agentID the ID of the agent
   */
  function agentBeneficiary(uint256 agentID) external view returns (AgentBeneficiary memory) {
    return _agentBeneficiaries[agentID];
  }

  /**
   * @notice `changeAgentBeneficiary` changes the beneficiary of an agent
   * @param beneficiary the address of the beneficiary
   * @param agentID the ID of the agent
   * @param expiration the epoch expiration of the beneficiary
   * @param quota the FIL quota of the beneficiary
   */
  function changeAgentBeneficiary(
    address beneficiary,
    uint256 agentID,
    uint256 expiration,
    uint256 quota
  ) external onlyAgent {
    AgentBeneficiary memory benny = _agentBeneficiaries[agentID];

    // if you already have a beneficiary addres set, you can't change it
    if (benny.isActive()) revert Unauthorized();
    // as long as we do not have an existing, active beneficiary, propose a new one
    _agentBeneficiaries[agentID] = benny.propose(beneficiary.normalize(), quota, expiration);
  }

  /**
   * @notice `approveAgentBeneficiary` converts the proposed beneficiary to the active beneficiary
   * @param agentID the ID of the agent
   * @dev must be called by the proposed beneficiary
   */
  function approveAgentBeneficiary(uint256 agentID) external {
    _agentBeneficiaries[agentID] = _agentBeneficiaries[agentID].approve(msg.sender);
  }

  /**
   * @notice `beneficiaryWithdrawable` is called by the Agent during withdraw when there is an active beneficiary. It withdraws funds to the beneficiary address and updates the beneficiary's quota in storage
   * @param recipient the address of the recipient
   * @param sender the address of the sender
   * @param agentID the ID of the agent
   * @param proposedAmount the amount of FIL the beneficiary is proposing to withdraw
   * @dev the agent's owner can force a beneficiary withdrawal if it calls this function when the receipient is the active beneficiary
   */
  function beneficiaryWithdrawable(
    address recipient,
    address sender,
    uint256 agentID,
    uint256 proposedAmount
  ) external returns (
    uint256 amount
  ) {
    AgentBeneficiary memory beneficiary = _agentBeneficiaries[agentID];
    address benneficiaryAddress = beneficiary.active.beneficiary;
    // If the sender is not the owner of the Agent or the beneficiary, revert
    if(
      !(benneficiaryAddress == sender || (IAuth(msg.sender).owner() == sender && recipient == benneficiaryAddress) )) {
        revert Unauthorized();
      }
    (
      beneficiary,
      amount
    ) = beneficiary.withdraw(proposedAmount);
    // update the beneficiary in storage
    _agentBeneficiaries[agentID] = beneficiary;
  }

  /**
   * @notice `confirmRmEquity` checks to see if a withdrawal will bring the agent over maxDTE
   * @param vc the verifiable credential
   * @param additionalLiability any additional liability to apply to the agent (used when removing a miner with an active beneficiary)
   */
  function confirmRmEquity(
    VerifiableCredential memory vc,
    uint256 additionalLiability
  ) external view {
    // check to ensure we can withdraw from this pool
    _agentApproved(vc);
    // check to ensure the withdrawal does not bring us over maxDTE
    address credParser = address(GetRoute.credParser(router));
    // check to make sure the after the withdrawal, the DTE is under max
    // the additionalLiability is used when an Agent wants to remove a miner
    // but an active beneficiary is set
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
    if (((principal + additionalLiability) * WAD) / (agentTotalValue - principal) > maxDTE) {
      revert AgentStateRejected();
    }
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

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  /// @dev computes the pro-rata split of a total amount based on principal
  function _writeOffPools(
    uint256 _agentID,
    uint256 _totalAmount
  ) internal {
    // Setup the variables we use in the loops here to save gas
    uint256 totalPrincipal;
    uint256 i;
    uint256 poolID;
    uint256 poolShare;
    uint256 principal;
    IWFIL wFIL = GetRoute.wFIL(router);

    uint256[] memory _pools = _poolIDs[_agentID];
    uint256 poolCount = _pools.length;

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
      wFIL.approve(address(GetRoute.pool(router, poolID)), poolShare);
      // write off the pool's assets
      GetRoute.pool(router, poolID).writeOff(_agentID, poolShare);
    }
  }

  /// @dev returns true if any pool has an `epochsPaid` behind `targetEpoch` (and thus is underpaid)
  function _epochsPaidBehindTarget(
    uint256 _agentID,
    uint256 _targetEpoch
  ) internal view returns (bool) {
    uint256[] memory pools = _poolIDs[_agentID];

    for (uint256 i = 0; i < pools.length; ++i) {
      if (AccountHelpers.getAccount(router, _agentID, pools[i]).epochsPaid < block.number - _targetEpoch) {
        return true;
      }
    }

    return false;
  }

  /// @dev loops through the pools and calls isApproved on each, reverting in the case of any non-approvals
  function _agentApproved(VerifiableCredential memory vc) internal view {
    uint256[] memory pools = _poolIDs[vc.subject];

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

  function createKey(string memory partitionKey, uint256 agentID) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, agentID));
  }
}
