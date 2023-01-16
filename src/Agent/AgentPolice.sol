// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AuthController} from "src/Auth/AuthController.sol";
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
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
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

contract AgentPolice is IAgentPolice, VCVerifier {
  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;

  uint256 public windowLength;

  // internally our mappings use AgentID to make upgrading easier
  // TODO: use bytes32/uint256 to store agent state in one uint256 like MRA
  mapping (uint256 => bool) private _isOverPowered;
  mapping (uint256 => bool) private _isOverLeveraged;

  mapping (uint256 => uint256[]) private _poolIDs;

  constructor(
    string memory _name,
    string memory _version,
    uint256 _windowLength
  ) VCVerifier(_name, _version) {
    windowLength = _windowLength;
  }

  modifier _isValidCredential(address agent, SignedCredential memory signedCredential) {
    _checkCredential(agent, signedCredential);
    _;
  }

  modifier requiresAuth() {
    _requiresAuth();
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

  function poolIDs(uint256 agentID) external view returns (uint256[] memory) {
    return _poolIDs[agentID];
  }

  function windowInfo() external view returns (Window memory) {
    uint256 deadline = nextPmtWindowDeadline();
    return Window(deadline - windowLength, deadline, windowLength);
  }

  // the first window deadline is epoch 0 + windowLength
  function nextPmtWindowDeadline() public view returns (uint256) {
    return (windowLength + block.number - (block.number % windowLength));
  }

  function isOverPowered(address agent) public view returns (bool) {
    return isOverPowered(_addressToID(agent));
  }

  function isOverPowered(uint256 agent) public view returns (bool) {
    return _isOverPowered[agent];
  }

  function isOverLeveraged(address agent) public view returns (bool) {
    return isOverLeveraged(_addressToID(agent));
  }

  function isOverLeveraged(uint256 agent) public view returns (bool) {
    return _isOverLeveraged[agent];
  }

  function isInDefault(uint256 agentID) public view returns (bool) {
    return isOverPowered(agentID) && isOverLeveraged(agentID);
  }

  function isInDefault(address agent) public view returns (bool) {
    return isInDefault(_addressToID(agent));
  }

  /*//////////////////////////////////////////////
                      CHECKERS
  //////////////////////////////////////////////*/

  function checkPower(
    address agent,
    SignedCredential memory signedCredential
  ) public _isValidCredential(agent, signedCredential) returns (bool) {
    bool overPowered = _updateOverPowered(agent, signedCredential);
    emit CheckPower(agent, msg.sender, overPowered);
    return overPowered;
  }

  function checkLeverage(
    address agent,
    SignedCredential memory signedCredential
  ) _isValidCredential(agent, signedCredential) public returns (bool) {
    uint256 agentID = AccountHelpers.agentAddrToID(agent);
    bool overLeveraged = _updateOverLeveraged(agentID, signedCredential);
    emit CheckLeverage(agent, msg.sender, overLeveraged);
    return overLeveraged;
  }

  function checkDefault(address agent, SignedCredential memory signedCredential) public {
    bool overPowered = checkPower(agent, signedCredential);
    bool overLeveraged = checkLeverage(agent, signedCredential);

    if (overPowered && overLeveraged) {
      uint256 liquidationValue = signedCredential.vc.miner.assets - signedCredential.vc.miner.liabilities;
      // write down each pool by the power token stake weight of the agent liquidation value
      _proRataPoolRebalance(agent, liquidationValue);
    }

    emit CheckDefault(agent, msg.sender, isInDefault(agent));
  }

  function isValidCredential(
    address agent,
    SignedCredential memory signedCredential
  ) external view returns (bool) {
    return isValid(
      agent,
      signedCredential.vc,
      signedCredential.v,
      signedCredential.r,
      signedCredential.s
    );
  }

  /*//////////////////////////////////////////////
                      POLICING
  //////////////////////////////////////////////*/

  /// @dev - the Agent itself checks to ensure no duplicate entries are added here
  function addPoolToList(uint256 pool) public onlyAgent {
    _poolIDs[_addressToID(msg.sender)].push(pool);
  }

  function removePoolFromList(uint256 pool) public onlyAgent {
    uint256[] storage pools = _poolIDs[_addressToID(msg.sender)];
    for (uint256 i = 0; i < pools.length; i++) {
      if (pools[i] == pool) {
        pools[i] = pools[pools.length - 1];
        pools.pop();
        break;
      }
    }
  }

  // not protected - anyone can call when the conditions permit
  function forceBurnPower(
    address agent,
    SignedCredential memory signedCredential
  ) external _isValidCredential(agent, signedCredential)  {
    uint256 agentID = _addressToID(agent);
    _revertIfNotOverPowered(agentID);

    // Compute the amount to burn
    IERC20 powerToken = GetRoute.powerToken20(router);
    uint256 underPowerAmt = _powerTokensMinted(agentID) - signedCredential.vc.miner.qaPower;
    uint256 powerTokensLiquid = powerToken.balanceOf(agent);
    uint256 burnAmount = powerTokensLiquid >= underPowerAmt
      ? underPowerAmt
      : powerTokensLiquid;

    // burn the amount
    uint256 amountBurned = IAgent(agent).burnPower(burnAmount, signedCredential);

    // TODO: Is this at risk of reentrancy? Doesn't seem like it, since we know the agent is an agent, and the power token is the power token..
    // set overPowered if needed
    bool stillOverPowered = _updateOverPowered(agent, signedCredential);

    emit ForceBurnPower(agent, msg.sender, amountBurned, stillOverPowered);
  }

  // only police admin can call (to start), to later decentralize this call
  // will draw down the maximum amounts possible from the miners to make payments
  function forceMakePayments(
    address agent,
    SignedCredential memory signedCredential
  ) external
    _isValidCredential(agent, signedCredential)
    requiresAuth
    onlyIfAgentOverLeveraged(agent)
  {
    uint256 totalPmt = GetRoute.wFIL20(router).balanceOf(agent);
    // then, we create a pro-rata split based on power token stakes to pay back each pool thats been borrowed from
    (uint256[] memory pools, uint256[] memory pmts) = _computeProRataAmts(agent, totalPmt);

    IAgent(agent).makePayments(pools, pmts, signedCredential);

    bool stillOverLeveraged = _updateLeverageTable(agent, signedCredential);

    emit ForceMakePayments(agent, msg.sender, pools, pmts, stillOverLeveraged);
  }

  function forcePullFundsFromMiners(
    address agent,
    address[] calldata miners,
    uint256[] calldata amounts
  ) external requiresAuth onlyIfAgentOverLeveraged(agent) {

    // draw up funds from all the agent's miners (non destructive)
    IAgent(agent).pullFundsFromMiners(miners, amounts);

    emit ForcePullFundsFromMiners(agent, miners, amounts);
  }

  // only operator / owner can call
  function lockout(
    address agent
  ) external requiresAuth onlyIfAgentInDefault(agent) {
    emit Lockout(agent, msg.sender);
  }

  /*//////////////////////////////////////////////
                  ADMIN CONTROLS
  //////////////////////////////////////////////*/

  function setWindowLength(uint256 _windowLength) external requiresAuth {
    windowLength = _windowLength;
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  function _computeProRataAmts(
    address _agent,
    uint256 _totalAmount
  ) internal view returns (
    uint256[] memory _pools,
    uint256[] memory _amts
  ) {
    IAgent agent = IAgent(_agent);
    uint256 poolCount = agent.stakedPoolsCount();

    _amts = new uint256[](poolCount);

    uint256 powerTokensStaked = agent.totalPowerTokensStaked();

    for (uint256 i = 0; i < poolCount; ++i) {
      _pools[i] = i;
      _amts[i] = _totalAmount * (agent.powerTokensStaked(_pools[i]) / powerTokensStaked);
    }
  }

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

  function _updateLeverageTable(
    address agent,
    SignedCredential memory sc
  ) internal returns (bool) {

  }

  function _updateOverPowered(
    address agent,
    SignedCredential memory sc
  ) internal returns (bool) {
    bool overPowered = sc.vc.miner.qaPower < _powerTokensMinted(agent);

    _isOverPowered[_addressToID(agent)] = overPowered;

    return overPowered;
  }

  function _addressToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _requiresAuth() internal view {
    if (!AuthController.canCallSubAuthority(router, address(this))) {
      revert Unauthorized(
        address(this),
        msg.sender,
        msg.sig,
        "AgentPolice: Unauthorized"
      );
    }
  }

  function _powerTokensMinted(uint256 agent) internal view returns (uint256) {
    return GetRoute.powerToken(router).powerTokensMinted(agent);
  }

  function _powerTokensMinted(address agent) internal view returns (uint256) {
    return _powerTokensMinted(_addressToID(agent));
  }

  function _updateOverLeveraged(
    uint256 agentID,
    SignedCredential memory signedCredential
  ) internal returns (bool) {
    Window memory window = GetRoute.agentPolice(router).windowInfo();
    uint256 totalOwed;

    uint256[] memory stakedPools = _poolIDs[agentID];
    // loop through all and add up all the owed amounts to get to the next window close
    for (uint256 i = 0; i < stakedPools.length; ++i) {
      totalOwed += AccountHelpers.getAccount(
        router,
        agentID,
        stakedPools[i]
      ).getMinPmtForWindowClose(
        window,
        router,
        IPoolImplementation(GetRoute.poolFactory(router).allPools(stakedPools[i]))
      );
    }

    // if the agent owes more than their total expected rewards, they're overleveraged
    bool overLeveraged = totalOwed > signedCredential.vc.miner.expectedDailyRewards;

    _isOverLeveraged[agentID] = overLeveraged;
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
        revert InvalidCredential(
          signedCredential,
          "AgentPolice: Invalid credential"
        );
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
}
