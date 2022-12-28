// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {AuthController} from "src/Auth/AuthController.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";

contract AgentPolice is IAgentPolice, VCVerifier {
  uint256 public windowLength;

  // internally our mappings use AgentID to make upgrading easier
  // TODO: use bytes32/uint256 to store agent state in one uint256 like MRA
  mapping (uint256 => bool) private _isOverPowered;
  mapping (uint256 => bool) private _isOverLeveraged;

  constructor(
    string memory _name,
    string memory _version,
    uint256 _windowLength
  ) VCVerifier(_name, _version) {
    windowLength = _windowLength;
  }

  modifier _isValidCredential(address agent, SignedCredential memory signedCredential) {
    require(
      isValid(
        agent,
        signedCredential.vc,
        signedCredential.v,
        signedCredential.r,
        signedCredential.s
      ),
      "AgentPolice: Invalid credential"
    );
    _;
  }

  modifier requiresAuth() {
    _requiresAuth();
    _;
  }

  // the first window deadline is epoch 0 + windowLength
  function nextPmtWindowDeadline() external view returns (uint256) {
    return block.number + (block.number % windowLength);
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
  ) public _isValidCredential(agent, signedCredential) {
    bool overPowered = _updatePowerTable(agent, signedCredential);
    emit CheckPower(agent, msg.sender, overPowered);
  }

  // TODO:
  function checkLeverage(address agent, SignedCredential memory signedCredential) public {
    uint256 agentToID = _addressToID(agent);

    emit CheckLeverage(agent, msg.sender, false);
  }

  function checkDefault(address agent, SignedCredential memory signedCredential) public {
    // this is where if the agent is in default, we write down to MLV in the pools' accounts
    // @ganzai this is where we can write down the token price
    emit CheckDefault(agent, msg.sender, isInDefault(agent));
  }

  function isValidCredential(address agent, SignedCredential memory signedCredential) external view returns (bool) {
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

  // not protected - anyone can call when the conditions permit
  function forceBurnPower(
    address agent,
    SignedCredential memory signedCredential
  ) external _isValidCredential(agent, signedCredential)  {
    require(isOverPowered(agent), "AgentPolice: Agent is not overpowered");

    // Compute the amount to burn
    IERC20 powerToken = GetRoute.powerToken20(router);
    uint256 underPowerAmt = IAgent(agent).powerTokensMinted() - signedCredential.vc.miner.qaPower;
    uint256 powerTokensLiquid = powerToken.balanceOf(agent);
    uint256 burnAmount = powerTokensLiquid >= underPowerAmt
      ? underPowerAmt
      : powerTokensLiquid;

    // burn the amount
    uint256 amountBurned = IAgent(agent).burnPower(burnAmount, signedCredential);

    // TODO: Is this at risk of reentrancy? Doesn't seem like it, since we know the agent is an agent, and the power token is the power token..
    // set overPowered if needed
    bool stillOverPowered = _updatePowerTable(agent, signedCredential);

    emit ForceBurnPower(agent, msg.sender, amountBurned, stillOverPowered);
  }

  // only police admin can call (to start), to later decentralize this call
  // will draw down the maximum amounts possible from the miners to make payments
  function forceMakePayments(
    address agent,
    SignedCredential memory signedCredential
  ) external _isValidCredential(agent, signedCredential) requiresAuth {
    require(isOverLeveraged(agent), "AgentPolice: Agent is not overleveraged");

    // then, we create a pro-rata split based on power token stakes to pay back each pool thats been borrowed from
    (uint256[] memory poolIDs, uint256[] memory pmts) = _computeProRataPmts(agent);

    IAgent(agent).makePayments(poolIDs, pmts, signedCredential);

    bool stillOverLeveraged = _updateLeverageTable(agent, signedCredential);

    emit ForceMakePayments(agent, msg.sender, poolIDs, pmts, stillOverLeveraged);
  }

  function forcePullFundsFromMiners(
    address agent,
    address[] calldata miners,
    uint256[] calldata amounts
  ) external requiresAuth {
    require(isOverLeveraged(agent), "AgentPolice: Agent is not overleveraged");

    // draw up funds from all the agent's miners (non destructive)
    IAgent(agent).pullFundsFromMiners(miners, amounts);

    emit ForcePullFundsFromMiners(agent, miners, amounts);
  }

  // only operator / owner can call
  function lockout(
    address agent
  ) external requiresAuth {
    require(isInDefault(agent), "AgentPolice: Agent is not in default");

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

  function _computeProRataPmts(
    address agent
  ) internal view returns (
    uint256[] memory poolIDs,
    uint256[] memory pmts
  ) {
    uint256 poolCount = IAgent(agent).stakedPoolsCount();

    uint256 totalPmt = GetRoute.wFIL20(router).balanceOf(agent);
    pmts = new uint256[](poolCount);

    for (uint256 i = 0; i < poolCount; ++i) {
      pmts[i] = totalPmt * (IAgent(agent).powerTokensStaked(poolIDs[i]) / IAgent(agent).totalPowerTokensStaked());
    }
  }

  function _updateLeverageTable(
    address agent,
    SignedCredential memory sc
  ) internal returns (bool) {

  }

  function _updatePowerTable(
    address agent,
    SignedCredential memory sc
  ) internal returns (bool) {
    bool overPowered = sc.vc.miner.qaPower < IAgent(agent).powerTokensMinted();

    _isOverPowered[_addressToID(agent)] = overPowered;

    return overPowered;
  }

  function _addressToID(address agent) internal view returns (uint256) {
    return IAgent(agent).id();
  }

  function _requiresAuth() internal view {
    require(
      AuthController.canCallSubAuthority(router, address(this)),
      "AgentPolice: Not authorized"
    );
  }
}
