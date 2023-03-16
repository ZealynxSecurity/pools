// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {AccountHelpersV2} from "src/Pool/AccountV2.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential, Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Roles} from "src/Constants/Roles.sol";
import {
  InvalidCredential,
  NotOverPowered,
  NotOverLeveraged,
  NotInDefault,
  Unauthorized
} from "src/Errors.sol";
import {ROUTE_CRED_PARSER } from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

string constant POWER = "POWER";
string constant LEVERAGE = "LEVERAGE";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable {
  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;

  /// @notice `windowLength` is the number of epochs between window.start and window.deadline
  uint256 public windowLength;

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
    uint256 _windowLength,
    uint256 _defaultWindow,
    address _owner,
    address _operator
  ) VCVerifier(_name, _version) Operatable(_owner, _operator) {
    windowLength = _windowLength;
    defaultWindow = _defaultWindow;
    maxPoolsPerAgent = 10;
  }

  modifier _isValidCredential(address agent, SignedCredential memory signedCredential) {
    _checkCredential(agent, signedCredential);
    _;
  }

  modifier onlyAgent() {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  modifier onlyIfAgentOverLeveraged(address agent) {
    _revertIfNotOverLeveraged(_addressToID(agent));
    _;
  }

  modifier onlyIfAgentInDefault(address agent) {
    _revertIfNotInDefault(_addressToID(agent));
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
   * @notice `windowInfo` returns the current window start, length, and deadline
   */
  function windowInfo() public view returns (Window memory) {
    uint256 deadline = nextPmtWindowDeadline();
    return Window(deadline - windowLength, deadline, windowLength);
  }

  /**
   * @notice `nextPmtWindowDeadline` returns the first window deadline is epoch 0 + windowLength
   */
  function nextPmtWindowDeadline() public view returns (uint256) {
    return (windowLength + block.number - (block.number % windowLength));
  }

  /**
   * @notice `isOverPowered` returns true if the agent has minted more power than they have in real quality adjusted power
   * @param agent the address of the agent
   */
  function isOverPowered(address agent) public view returns (bool) {
    return isOverPowered(_addressToID(agent));
  }

  /**
   * @notice `isOverPowered` returns true if the agent has minted more power than they have in real quality adjusted power
   * @param agent the ID of the agent
   */
  function isOverPowered(uint256 agent) public view returns (bool) {
    return _agentState[createKey(POWER, agent)];
  }

  /**
   * @notice `isOverLeveraged` returns true if the agent owes more in total to all pool than they expect to earn in the same window period
   * @param agent the address of the agent
   */
  function isOverLeveraged(address agent) public view returns (bool) {
    return isOverLeveraged(_addressToID(agent));
  }

  /**
   * @notice `isOverLeveraged` returns true if the agent owes more in total to all pool than they expect to earn in the same window period
   * @param agent the ID of the agent
   */
  function isOverLeveraged(uint256 agent) public view returns (bool) {
    return _agentState[createKey(LEVERAGE, agent)];
  }

  /**
   * @notice `isInDefault` returns true if the agent is overPowered and overLeveraged
   * @param agent the ID of the agent
   */
  function isInDefault(uint256 agent) public view returns (bool) {
    return isOverPowered(agent) && isOverLeveraged(agent);
  }

  /**
   * @notice `isInDefault` returns true if the agent is overPowered and overLeveraged
   * @param agent the address of the agent
   */
  function isInDefault(address agent) public view returns (bool) {
    return isInDefault(_addressToID(agent));
  }

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  /**
   * @notice `checkPower` updates the overPowered state of the agent and returns true if they are overpowered
   * @param agent the address of the agent
   * @param signedCredential the signed credential of the agent
   */
  function checkPower(
    address agent,
    SignedCredential memory signedCredential
  ) public _isValidCredential(agent, signedCredential) returns (bool) {
    bool overPowered = _updateOverPowered(agent, signedCredential);
    emit CheckPower(agent, msg.sender, overPowered);
    return overPowered;
  }

  /**
   * @notice `checkLeverage` updates the overLeveraged state of the agent and returns true if they are overLeveraged
   * @param agent the address of the agent
   * @param signedCredential the signed credential of the agent
   *
   * @dev an agent is overleveraged if they owe more in total to all pools than they expect to earn in the same window period
   * the agent's expectedDailyRewards as computed in the `signedCredential` are applied to the window period
   */
  function checkLeverage(
    address agent,
    SignedCredential memory signedCredential
  ) _isValidCredential(agent, signedCredential) public returns (bool) {
    uint256 agentID = AccountHelpers.agentAddrToID(agent);
    bool overLeveraged = _updateOverLeveraged(agentID, signedCredential);
    emit CheckLeverage(agent, msg.sender, overLeveraged);
    return overLeveraged;
  }

  function isAgentOverLeveraged(
    uint256 agentID,
    VerifiableCredential memory vc
  ) external view {
    uint256[] memory poolIDs = _poolIDs(agentID);

    for (uint256 i = 0; i < poolIDs.length; ++i) {
      uint256 poolID = poolIDs[i];
      IPool pool = GetRoute.pool(router, poolID);
      if (pool.implementation().isOverLeveraged(
        AccountHelpersV2.getAccount(router, agentID, poolID),
        vc
      )) {
        revert OverLeveraged();
      }
    }
  }

  // function checkDefaultV2(address agent) external view returns (bool) {
  //   return _checkDefaultV2(_addressToID(agent));
  // }

  /**
   * @notice `checkDefault` updates the overPowered and overLeveraged state of the agent and returns true if they are both true (in default)
   * @param agent the address of the agent
   * @param signedCredential the signed credential of the agent
   */
  function checkDefault(address agent, SignedCredential memory signedCredential) public {
    bool overPowered = checkPower(agent, signedCredential);
    bool overLeveraged = checkLeverage(agent, signedCredential);
    address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
    if (overPowered && overLeveraged) {
      uint256 liquidationValue = signedCredential.vc.getAssets(credParser) - signedCredential.vc.getLiabilities(credParser);
      // write down each pool by the power token stake weight of the agent liquidation value
      _proRataPoolRebalance(agent, liquidationValue);
    }

    emit CheckDefault(agent, msg.sender, isInDefault(agent));
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
      _checkCredential(agent, signedCredential);
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
    if (GetRoute.pool(router, pool) != msg.sender) {
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
   * @notice `forceBurnPower` burns any liquid power tokens on the Agnet's behalf. It does not burn any tokens staked in pools.
   * @param agent the address of the agent to burn power
   * @param signedCredential the signed credential of the agent
   * @dev An agent must be overPowered to force burn their power
   * This method is not protected - anyone can call when the conditions permit
   */
  function forceBurnPower(
    address agent,
    SignedCredential memory signedCredential
  ) external _isValidCredential(agent, signedCredential)  {
    uint256 agentID = _addressToID(agent);
    _revertIfNotOverPowered(agentID);

    // Compute the amount to burn
    IERC20 powerToken = GetRoute.powerToken20(router);
    uint256 underPowerAmt = _powerTokensMinted(agentID) - signedCredential.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER));
    uint256 powerTokensLiquid = powerToken.balanceOf(agent);
    uint256 burnAmount = powerTokensLiquid >= underPowerAmt
      ? underPowerAmt
      : powerTokensLiquid;

    // burn the amount
    uint256 amountBurned = IAgent(agent).burnPower(burnAmount, signedCredential);

    // set overPowered if needed
    bool stillOverPowered = _updateOverPowered(agent, signedCredential);

    emit ForceBurnPower(agent, msg.sender, amountBurned, stillOverPowered);
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
    onlyIfAgentOverLeveraged(agent)
  {
    IAgent _agent = IAgent(agent);
    // then, we create a pro-rata split based on power token stakes to pay back each pool thats been borrowed from
    (
      uint256[] memory pools,
      uint256[] memory pmts
    ) = _computeProRataAmts(agent, _totalOwed(_agent.id()));

    _agent.makePayments(pools, pmts, signedCredential);

    bool stillOverLeveraged = _updateOverLeveraged(_agent.id(), signedCredential);

    emit ForceMakePayments(agent, msg.sender, pools, pmts, stillOverLeveraged);
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
  ) external onlyOwnerOperator onlyIfAgentOverLeveraged(agent) {

    // draw up funds from all the agent's miners (non destructive)
    IAgent(agent).pullFundsFromMiners(miners, amounts, sc);

    emit ForcePullFundsFromMiners(agent, miners, amounts);
  }

  /**
   * @notice `lockout` remove all external control from a miner actor
   * @param agent the address of the agent to lock out
   * @param miner the miner to lock out
   * @dev An agent must be in default to lock out a miner, and only the agent police admin can call this function
   * The reason to lockout a miner is to terminate its sectors early to recoup as much funds as possible
   * It is a destructive action
   * TODO
   */
  function lockout(
    address agent,
    uint64 miner
  ) external onlyOwnerOperator onlyIfAgentInDefault(agent) {
    emit Lockout(agent, msg.sender);
  }

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  /**
   * @notice `setWindowLength` changes the window length
   */
  function setWindowLength(uint256 _windowLength) external onlyOwnerOperator {
    windowLength = _windowLength;
  }

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

    uint256 powerTokensStaked = agent.totalPowerTokensStaked();

    for (uint256 i = 0; i < poolCount; ++i) {
      _amts[i] = _totalAmount * (agent.powerTokensStaked(_pools[i]) / powerTokensStaked);
    }
  }

  /// @dev writes down the amount of assets a pool can expect from an agent
  function _proRataPoolRebalance(
    address _agent,
    uint256 _totalAmount
  ) internal {
    IAgent agent = IAgent(_agent);
    uint256 poolCount = agent.stakedPoolsCount();

    uint256 powerTokensStaked = agent.totalPowerTokensStaked();

    for (uint256 i = 0; i < poolCount; ++i) {
      uint256 realizeableValue = agent
        .powerTokensStaked(i)
        .divWadDown(powerTokensStaked)
        .mulWadDown(_totalAmount)
        .divWadDown(FixedPointMathLib.WAD);

      GetRoute.pool(router, i).rebalanceTotalBorrowed(agent.id(), realizeableValue);
    }
  }

  function _updateOverPowered(
    address agent,
    SignedCredential memory sc
  ) internal returns (bool) {
    uint256 agentID = _addressToID(agent);
    bool overPowered = sc.vc.getQAPower(IRouter(router).getRoute(ROUTE_CRED_PARSER)) < _powerTokensMinted(agentID);

    _agentState[createKey(POWER, agentID)] = overPowered;

    return overPowered;
  }

  function _addressToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _powerTokensMinted(uint256 agent) internal view returns (uint256) {
    return GetRoute.powerToken(router).powerTokensMinted(agent);
  }

  /// @dev returns the total amount owed across all pools to get to the next window close
  function _totalOwed(uint256 agentID) internal view returns (uint256 totalOwed) {
    uint256[] memory stakedPools = _poolIDs[agentID];
    // loop through all and add up all the owed amounts to get to the next window close
    for (uint256 i = 0; i < stakedPools.length; ++i) {
      totalOwed += AccountHelpers.getAccount(
        router,
        agentID,
        stakedPools[i]
      ).getMinPmtForWindowClose(
        windowInfo(),
        router,
        GetRoute.pool(router, stakedPools[i]).implementation()
      );
    }
  }

  function _updateOverLeveraged(
    uint256 agentID,
    SignedCredential memory signedCredential
  ) internal returns (bool) {
    // expected per epoch rewards = expected daily rewards / epochs in a day
    // expected earnings = expected per epoch rewards * epochs until window close
    uint256 perEpochExpRewards = signedCredential.vc.getExpectedDailyRewards(IRouter(router).getRoute(ROUTE_CRED_PARSER)) / EPOCHS_IN_DAY;
    uint256 expectedEarnings = perEpochExpRewards * (nextPmtWindowDeadline() - block.number);

    // if the agent owes more than their total expected rewards in the window period, they're overleveraged
    bool overLeveraged = _totalOwed(agentID) > expectedEarnings;

    _agentState[createKey(LEVERAGE, agentID)] = overLeveraged;

    return overLeveraged;
  }

  function _checkCredential(
    address agent,
    SignedCredential memory signedCredential
  ) internal view {
    if (!isValid(
        agent,
        signedCredential.vc,
        signedCredential.v,
        signedCredential.r,
        signedCredential.s
      )) {
        revert InvalidCredential();
      }
    if (_credentialUseBlock[keccak256(abi.encode(signedCredential.v, signedCredential.r, signedCredential.s))] > 0)  {
        revert InvalidCredential();
      }

  }

  function _revertIfNotOverPowered(uint256 agent) internal view {
    if (!isOverPowered(agent)) {
      revert NotOverPowered(agent, "AgentPolice: Agent is not overpowered");
    }
  }

  function _revertIfNotOverLeveraged(uint256 agent) internal view {
    if (!isOverLeveraged(agent)) {
      revert NotOverLeveraged(agent, "AgentPolice: Agent is not overleveraged");
    }
  }

  function _revertIfNotInDefault(uint256 agent) internal view {
    if (!isOverPowered(agent) || !isOverLeveraged(agent)) {
      revert NotInDefault(agent, "AgentPolice: Agent is not in default");
    }
  }

  function createKey(string memory partitionKey, uint256 agentID) internal pure returns (bytes32) {
    return keccak256(abi.encode(partitionKey, agentID));
  }
}
