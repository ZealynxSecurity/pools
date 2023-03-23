// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential, Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Roles} from "src/Constants/Roles.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable {

  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;

  error OverLeveraged();
  error Unauthorized();

  /// @notice `defaultLookback` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is in default
  uint256 public defaultWindow;

  /// @notice `maxPoolsPoerAgent`
  uint256 public maxPoolsPerAgent;

  /// @notice `_liquidated` maps agentID to whether the liquidation process has been completed
  mapping(uint256 => bool) public liquidated;

  /// @notice `_poolIDs` maps agentID to the pools they have actively borrowed from
  mapping(uint256 => uint256[]) private _poolIDs;

  /// @notice `_credentialUseBlock` maps signature bytes to when a credential was used
  mapping(bytes32 => uint256) private _credentialUseBlock;

  constructor(
    string memory _name,
    string memory _version,
    uint256 _defaultWindow,
    address _owner,
    address _operator
  ) VCVerifier(_name, _version) Operatable(_owner, _operator) {
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

  function isAgentOverLeveraged(
    VerifiableCredential memory vc
  ) external view {
    uint256[] memory pools = _poolIDs[vc.subject];

    for (uint256 i = 0; i < pools.length; ++i) {
      uint256 poolID = pools[i];
      IPool pool = GetRoute.pool(router, poolID);
      if (pool.isOverLeveraged(
        AccountHelpers.getAccount(router, vc.subject, poolID),
        vc
      )) {
        revert OverLeveraged();
      }
    }
  }

  /**
   * @notice `setAgentDefaulted` puts the agent in default permanently
   * @param agent The address of the agent to put in default
   */
  function setAgentDefaulted(address agent) external onlyOwnerOperator onlyWhenBehindTargetEpoch(agent) {
    IAgent(agent).setInDefault();
    emit Defaulted(agent);
  }

  /**
   * @notice `putAgentOnAdministration` puts the agent on administration, hopefully only temporarily
   * @param agent The address of the agent to put on administration
   */
  function putAgentOnAdministration(
    address agent, address administration
  ) external
    onlyOwnerOperator
    onlyWhenBehindTargetEpoch(agent)
  {
    IAgent(agent).setAdministration(administration);
    emit OnAdministration(agent);
  }

  /**
   * @notice `rmAgentFromAdministration` removes the agent from administration
   * @param agent The address of the agent to remove from administration
   */
  function rmAgentFromAdministration(address agent) external onlyOwnerOperator {
    if (_epochsPaidBehindTarget(IAgent(agent).id(), defaultWindow)) revert Unauthorized();

    IAgent(agent).setAdministration(address(0));
    emit OffAdministration(agent);
  }

  function prepareMinerForLiquidation(address agent, address liquidator, uint64 miner) external onlyOwnerOperator {
    IAgent(agent).prepareMinerForLiquidation(miner, liquidator);
  }

  function distributeLiquidatedFunds(uint256 agentID, uint256 amount) external {
    if (!liquidated[agentID]) revert Unauthorized();

    // transfer the assets into the pool
    SafeTransferLib.safeTransferFrom(
      ERC20(address(GetRoute.wFIL(router))),
      msg.sender,
      address(this),
      amount
    );

    _writeOffPools(agentID, amount);
  }

  function liquidatedAgent(address agent) external onlyOwnerOperator {
    if (!IAgent(agent).defaulted()) revert Unauthorized();

    liquidated[IAgent(agent).id()] = true;
  }

  /**
   * @notice `isValidCredential` returns true if the credential is valid
   * @param agent the ID of the agent
   * @param signedCredential the signed credential of the agent
   * @dev a credential is valid if it's subject is `agent` and is signed by an authorized issuer
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

    if (
      _credentialUseBlock[
        keccak256(abi.encode(
          signedCredential.v, signedCredential.r, signedCredential.s
        ))
      ] > 0
    ) revert InvalidCredential();
  }

  function registerCredentialUseBlock(SignedCredential memory signedCredential) external  {
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
  function addPoolToList(uint256 pool) public onlyAgent {
    _poolIDs[_addressToID(msg.sender)].push(pool);
  }

  /**
   * @notice `removePoolFromList` removes a pool from an agent's list of pools its borrowed from
   * @param pool the id of the pool to add
   * @dev only an agent can add a pool to its list
   */
  function removePoolFromList(uint256 agentID, uint256 pool) external {
    if (address(GetRoute.pool(router, pool)) != msg.sender) {
      revert Unauthorized();
    }

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
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  /**
   * @notice `setDefaultWindow` changes the default window epochs
   */
  function setDefaultWindow(uint256 _defaultWindow) external onlyOwnerOperator {
    defaultWindow = _defaultWindow;
  }

  /**
   * @notice `setMaxPoolsPerAgent` changes the maximum number of pools an agent can borrow from
   */
  function setMaxPoolsPerAgent(uint256 _maxPoolsPerAgent) external onlyOwnerOperator {
    maxPoolsPerAgent = _maxPoolsPerAgent;
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

  function _addressToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function createKey(string memory partitionKey, uint256 agentID) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, agentID));
  }
}
