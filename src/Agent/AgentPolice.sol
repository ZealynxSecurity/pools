// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential, Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_CRED_PARSER } from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

string constant POWER = "POWER";
string constant LEVERAGE = "LEVERAGE";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable {

  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;

  error OverLeveraged();
  error NotAuthorized();

  /// @notice `defaultLookback` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is in default
  uint256 public defaultWindow;
  /// @notice `maxPoolsPoerAgent`
  uint256 public maxPoolsPerAgent;

  /// @notice `_agentState` maps agentID to whether they are overpowered or overleveraged
  mapping(bytes32 => bool) private _agentState;
  /// @notice `_poolIDs` maps agentID to the pools they have actively borrowed from
  mapping(uint256 => uint256[]) private _poolIDs;
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

  /// @dev this modifier takes
  modifier _isValidCredential(address agent, SignedCredential memory signedCredential) {
    _checkCredential(_addressToID(agent), signedCredential);
    _;
  }

  modifier onlyAgent() {
    AuthController.onlyAgent(router, msg.sender);
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

  /**
   * @notice `isInDefault` returns true if the agent is overPowered and overLeveraged
   * @param agent the ID of the agent

   TODO:
   */
  function isInDefault(uint256 agent) public view returns (bool) {
    return false;
  }

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  function isAgentOverLeveraged(
    uint256 agentID,
    VerifiableCredential memory vc
  ) external view {
    uint256[] memory poolIDs = _poolIDs[agentID];

    for (uint256 i = 0; i < poolIDs.length; ++i) {
      uint256 poolID = poolIDs[i];
      IPool pool = GetRoute.pool(router, poolID);
      if (pool.isOverLeveraged(
        AccountHelpers.getAccount(router, agentID, poolID),
        vc
      )) {
        revert OverLeveraged();
      }
    }
  }

  /**
   * @notice `checkDefault` TODO:
   * @param sc the signed credential of the agent
   */
  function checkDefault(SignedCredential memory sc) public returns (bool) {
    // bool overPowered = checkPower(agent, signedCredential);
    // bool overLeveraged = checkLeverage(agent, signedCredential);
    // address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    // if (overPowered && overLeveraged) {
    //   uint256 liquidationValue = signedCredential.vc.getAssets(credParser) - signedCredential.vc.getLiabilities(credParser);
    //   // write down each pool by the power token stake weight of the agent liquidation value
    //   _proRataPoolRebalance(agent, liquidationValue);
    // }
    return false;

    // emit CheckDefault(agent, msg.sender, isInDefault(agent));
  }

  /**
   * @notice `isValidCredential` returns true if the credential is valid
   * @param agent the address of the agent
   * @param signedCredential the signed credential of the agent
   * @dev a credential is valid if it's subject is `agent` and is signed by an authorized issuer
   */
  function isValidCredential(
    address agent,
    SignedCredential memory signedCredential
  ) external {
      _checkCredential(_addressToID(agent), signedCredential);
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
      revert NotAuthorized();
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

  /**
   * @notice `forceMakePayments` burns any liquid power tokens on the Agent's behalf. It does not burn any tokens staked in pools.
   * @param agent the address of the agent to burn power
   * @param signedCredential the signed credential of the agent
   * @dev An agent must be overPowered to force burn their power
   * To start this method is protected and callable only by the agent police admin
   * but once stable, can be decentralized
   */
  function forceMakePayments(
    address agent,
    SignedCredential memory signedCredential
  ) external
    onlyOwnerOperator
    _isValidCredential(agent, signedCredential)
    /// onlyIfAgentOverLeveraged(agent)
  {
    // IAgent _agent = IAgent(agent);
    // // then, we create a pro-rata split based on power token stakes to pay back each pool thats been borrowed from
    // (
    //   uint256[] memory pools,
    //   uint256[] memory pmts
    // ) = _computeProRataAmts(agent, _totalOwed(_agent.id()));

    // _agent.makePayments(pools, pmts, signedCredential);

    // bool stillOverLeveraged = _updateOverLeveraged(_agent.id(), signedCredential);

    // emit ForceMakePayments(agent, msg.sender, pools, pmts, stillOverLeveraged);
  }

  /**
   * @notice `forcePullFundsFromMiners` draws up funds from the agent's miners
   * @param agent the address of the agent to burn power
   * @param miners the miners to pull funds from
   * @param amounts the amounts of funds to pull from each miner
   * @dev An agent must be overLeveraged to force pull funds
   */
  function forcePullFundsFromMiners(
    address agent,
    uint64[] calldata miners,
    uint256[] calldata amounts,
    SignedCredential memory sc
  ) external
    onlyOwnerOperator
    /// onlyIfAgentOverLeveraged(agent)
  {
    // // draw up funds from all the agent's miners (non destructive)
    // IAgent(agent).pullFundsFromMiners(miners, amounts, sc);

    // emit ForcePullFundsFromMiners(agent, miners, amounts);
  }

  /**
   * @notice `lockout` remove all external control from a miner actor
   * @param agent the address of the agent to lock out
   * @param miner the miner to lock out
   * @dev An agent must be in default to lock out a miner, and only the agent police admin can call this function
   * The reason to lockout a miner is to terminate its sectors early to recoup as much funds as possible
   * It is a destructive action
   * TODO only if in default
   */
  function lockout(
    address agent,
    uint64 miner
  ) external
    onlyOwnerOperator
    /// onlyIfAgentInDefault(agent)
  {
    emit Lockout(agent, msg.sender);
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

  /// @dev computes the pro-rata split of a total amount based on power token stakes
  function _computeProRataAmts(
    address _agent,
    uint256 _totalAmount
  ) internal view returns (
    uint256[] memory _pools,
    uint256[] memory _amts
  ) {
    IAgent agent = IAgent(_agent);

    _pools = _poolIDs[agent.id()];
    uint256 poolCount = _pools.length;

    _amts = new uint256[](poolCount);

    // for (uint256 i = 0; i < poolCount; ++i) {
    //   _amts[i] = _totalAmount * (agent.powerTokensStaked(_pools[i]) / powerTokensStaked);
    // }
  }

  /// @dev writes down the amount of assets a pool can expect from an agent
  function _proRataPoolRebalance(
    address _agent,
    uint256 _totalAmount
  ) internal {
    IAgent agent = IAgent(_agent);
    uint256 poolCount = agent.borrowedPoolsCount();

    // uint256 powerTokensStaked = agent.totalPowerTokensStaked();

    // for (uint256 i = 0; i < poolCount; ++i) {
    //   uint256 realizeableValue = agent
    //     .powerTokensStaked(i)
    //     .divWadDown(powerTokensStaked)
    //     .mulWadDown(_totalAmount)
    //     .divWadDown(FixedPointMathLib.WAD);

    //   GetRoute.pool(router, i).rebalanceTotalBorrowed(agent.id(), realizeableValue);
    // }
  }

  function _addressToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _checkCredential(
    uint256 agent,
    SignedCredential memory signedCredential
  ) internal view {
    validateCred(
      agent,
      signedCredential.vc,
      signedCredential.v,
      signedCredential.r,
      signedCredential.s
    );

    if (_credentialUseBlock[keccak256(abi.encode(signedCredential.v, signedCredential.r, signedCredential.s))] > 0)  {
        revert InvalidCredential();
      }
  }

  function createKey(string memory partitionKey, uint256 agentID) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, agentID));
  }


}
