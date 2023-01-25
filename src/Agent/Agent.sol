// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {Authority} from "src/Auth/Auth.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IStats} from "src/Types/Interfaces/IStats.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IMockMiner} from "src/Types/Interfaces/IMockMiner.sol"; // TODO: remove this for Filecoin.sol
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {
  ChangeWorkerAddressParams,
  ChangeMultiaddrsParams,
  ChangePeerIDParams
} from "src/Types/Structs/Filecoin.sol";

import {
  ROUTE_AGENT_FACTORY,
  ROUTE_POWER_TOKEN,
  ROUTE_POOL_FACTORY,
  ROUTE_MINER_REGISTRY,
  ROUTE_WFIL_TOKEN,
  ROUTE_AGENT_POLICE
} from "src/Constants/Routes.sol";
import {Roles} from "src/Constants/Roles.sol";
import {
  OverPowered,
  OverLeveraged,
  InvalidParams,
  InDefault,
  InsufficientCollateral
} from "src/Errors.sol";

contract Agent is IAgent, RouterAware {
  uint256 public id;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth {
    _requiresAuth();
    _;
  }

  modifier requiresAuthOrPolice {
    _requiresAuthOrPolice();
    _;
  }

  modifier notOverPowered {
    _notOverPowered();
    _;
  }

  modifier notOverLeveraged {
    _notOverLeveraged();
    _;
  }

  modifier notInDefault {
    _notInDefault();
    _;
  }

  modifier isValidCredential(SignedCredential memory signedCredential) {
    _isValidCredential(address(this), signedCredential);
    _;
  }

  constructor(
    address _router,
    uint256 _agentID
  ) {
    router = _router;
    id = _agentID;
  }

  /*//////////////////////////////////////////////////
                        GETTERS
  //////////////////////////////////////////////////*/

  function powerTokensStaked(uint256 poolID) public view returns (uint256) {
    return AccountHelpers.getAccount(router, id, poolID).powerTokensStaked;
  }

  function hasMiner(address miner) public view returns (bool) {
    return GetRoute.minerRegistry(router).minerRegistered(id, miner);
  }

  function totalPowerTokensStaked() public view returns (uint256) {
    uint256[] memory poolIDs = _getStakedPoolIDs();
    uint256 staked = 0;
    for (uint256 i = 0; i < poolIDs.length; i++) {
      staked += powerTokensStaked(poolIDs[i]);
    }

    return staked;
  }

  // returns the number of pools the agent has an active staked in
  function stakedPoolsCount() external view returns (uint256) {
    return _getStakedPoolIDs().length;
  }

  // returns the amount of funds an Agent can withdraw from a pool
  function maxWithdraw(SignedCredential memory sc) external view returns (uint256) {
    return _maxWithdraw(sc.vc);
  }

  // returns the total amount of FIL + WFIL held currently by the Agent
  function liquidAssets() public view returns (uint256) {
    uint256 filBal = address(this).balance;
    uint256 wfilBal = GetRoute.wFIL20(router).balanceOf(address(this));
    return filBal + wfilBal;
  }

  /*//////////////////////////////////////////////
            PAYABLE / FALLBACK FUNCTIONS
  //////////////////////////////////////////////*/

  receive() external payable {}

  fallback() external payable {}

  /*//////////////////////////////////////////////////
        MINER OWNERSHIP/WORKER/OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function addMiners(address[] calldata miners) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      _addMiner(miners[i]);
    }
  }

  function removeMiner(
    address newMinerOwner,
    address miner,
    SignedCredential memory agentCred,
    // a credential uniquely about the miner we wish to remove
    SignedCredential memory minerCred
  )
    external
    notOverPowered
    notOverLeveraged
    requiresAuth
    isValidCredential(agentCred)
  {
    // also validate the minerCred against the miner to remove
    _isValidCredential(miner, minerCred);
    _checkRemoveMiner(agentCred.vc, minerCred.vc);

    // set the miners owner to the new owner
    _changeMinerOwner(miner, newMinerOwner);

    // Remove the miner from the central registry
    GetRoute.minerRegistry(router).removeMiner(miner);
  }

  function migrateMiner(address newAgent, address miner) external requiresAuth {
    uint256 newId = IAgent(newAgent).id();
    // first check to make sure the agentFactory knows about this "agent"
    require(GetRoute.agentFactory(router).agents(newAgent) == newId);
    // then make sure this is the same agent, just upgraded
    require(newId == id, "Cannot migrate miner to a different agent");
    // check to ensure this miner was registered to the original agent
    require(GetRoute.minerRegistry(router).minerRegistered(id, miner), "Miner not registered");
    // propose an ownership change (must be accepted in v2 agent)
    _changeMinerOwner(miner, newAgent);

    emit MigrateMiner(msg.sender, newAgent, miner);
  }

  function changeMinerWorker(
    address miner,
    ChangeWorkerAddressParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_worker_address(miner, params);
    emit ChangeMinerWorker(miner, params.new_worker, params.new_control_addresses);
  }

  function changeMultiaddrs(
    address miner,
    ChangeMultiaddrsParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_multiaddresses(miner, params);
    emit ChangeMultiaddrs(miner, params.new_multi_addrs);
  }

  function changePeerID(
    address miner,
    ChangePeerIDParams calldata params
  ) external requiresAuth {
    IMockMiner(miner).change_peer_id(miner, params);
    emit ChangePeerID(miner, params.new_id);
  }

  /*//////////////////////////////////////////////////
          AGENT OWNERSHIP / OPERATOR CHANGES
  //////////////////////////////////////////////////*/

  function setOperatorRole(address operator, bool enabled) external requiresAuth {
    IMultiRolesAuthority(
      address(AuthController.getSubAuthority(router, address(this)))
    ).setUserRole(operator, uint8(Roles.ROLE_AGENT_OPERATOR), enabled);

    emit SetOperatorRole(operator, enabled);
  }

  function setOwnerRole(address owner, bool enabled) external requiresAuth {
    IMultiRolesAuthority(
      address(AuthController.getSubAuthority(router, address(this)))
    ).setUserRole(owner, uint8(Roles.ROLE_AGENT_OWNER), enabled);

    emit SetOwnerRole(owner, enabled);
  }

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/

  function mintPower(
    uint256 amount,
    SignedCredential memory signedCredential
  ) external notOverPowered requiresAuth isValidCredential(signedCredential) {
    IPowerToken powerToken = GetRoute.powerToken(router);
    // check
    require(
      signedCredential.vc.miner.qaPower >= powerToken.powerTokensMinted(id) + amount,
      "Cannot mint more power than the miner has"
    );
    // interact
    powerToken.mint(amount);
  }

  function burnPower(
    uint256 amount,
    SignedCredential memory signedCredential
  ) external requiresAuthOrPolice isValidCredential(signedCredential) returns (uint256) {
    IERC20 powerToken = GetRoute.powerToken20(router);
    // check
    require(amount <= powerToken.balanceOf(address(this)), "Agent: Cannot burn more power than the agent holds");
    // interact
    IPowerToken(address(powerToken)).burn(amount);

    return amount;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/

  function withdrawBalance(address receiver, uint256 amount) external requiresAuth {
    require(totalPowerTokensStaked() == 0, "Cannot withdraw funds while power tokens are staked");

    _withdrawBalance(receiver, amount);
  }

  function withdrawBalance(
    address receiver,
    uint256 amount,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    uint256 maxWithdrawAmt = _maxWithdraw(signedCredential.vc);

    if (maxWithdrawAmt < amount) {
      revert InsufficientCollateral(
        address(this),
        msg.sender,
        amount,
        maxWithdrawAmt,
        msg.sig,
        "Attempted to draw down too much collateral"
      );
    }

    _withdrawBalance(receiver, amount);
  }

  function pullFundsFromMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external requiresAuthOrPolice {
    require(miners.length == amounts.length, "Miners and amounts must be same length");
    for (uint256 i = 0; i < miners.length; i++) {
      _pullFundsFromMiner(miners[i], amounts[i]);
    }

    emit PullFundsFromMiners(miners, amounts);
  }

  function pushFundsToMiners(
    address[] calldata miners,
    uint256[] calldata amounts
  ) external requiresAuth {
    require(miners.length == amounts.length, "Miners and amounts must be same length");

    uint256 total = 0;
    for (uint256 i = 0; i < miners.length; i++) {
      total += amounts[i];
    }

    _poolFundsInFIL(total);

    for (uint256 i = 0; i < miners.length; i++) {
      _pushFundsToMiner(miners[i], amounts[i]);
    }

    emit PushFundsToMiners(miners, amounts);
  }

  function borrow(
    uint256 amount,
    uint256 poolID,
    SignedCredential memory signedCredential,
    uint256 powerTokenAmount
  ) external
    notOverPowered
    notOverLeveraged
    notInDefault
    requiresAuth
    isValidCredential(signedCredential)
  {
    IPool pool = GetRoute.pool(router, poolID);

    // TODO: Use agent ID here instead of address
    // first time staking, add the poolID to the list of pools this agent is staking in
    if (pool.getAgentBorrowed(address(this)) == 0) {
      GetRoute.agentPolice(router).addPoolToList(poolID);
    }

    pool.borrow(amount, signedCredential, powerTokenAmount);
  }

  function refinance(
    uint256 oldPoolID,
    uint256 newPoolID,
    uint256 additionalPowerTokens,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    Account memory account = AccountHelpers.getAccount(
      router,
      address(this),
      oldPoolID
    );
    IPowerToken powerToken = GetRoute.powerToken(router);
    IPool oldPool = GetRoute.pool(router, oldPoolID);
    IPool newPool = GetRoute.pool(router, newPoolID);
    uint256 powerTokensStaked = account.powerTokensStaked;
    uint256 currentDebt = account.totalBorrowed;
    // NOTE: This could be dangerous, we need to protect against re-entrancy in the pool borrow. Might be better to do this.
    powerToken.mint(powerTokensStaked);
    newPool.borrow(currentDebt, signedCredential, powerTokensStaked + additionalPowerTokens);
    require(oldPool.exitPool(address(this), signedCredential, currentDebt) == powerTokensStaked, "Refinance failed");
    powerToken.burn(powerTokensStaked);
  }

  function exit(
    uint256 poolID,
    uint256 assetAmount,
    SignedCredential memory signedCredential
  ) external requiresAuth isValidCredential(signedCredential) {
    // TODO: optimize with https://github.com/glif-confidential/pools/issues/148
    IPool pool = GetRoute.pool(router, poolID);
    uint256 borrowedAmount = pool.getAgentBorrowed(address(this));

    require(borrowedAmount >= assetAmount, "Cannot exit more than borrowed");

    pool.getAsset().approve(address(pool), assetAmount);
    pool.exitPool(address(this), signedCredential, assetAmount);

    if (borrowedAmount == assetAmount) {
      // remove poolID from list of pools this agent is staking in
      GetRoute.agentPolice(router).removePoolFromList(poolID);
    }
  }

  function makePayments(
    uint256[] calldata _poolIDs,
    uint256[] calldata _amounts,
    SignedCredential memory _signedCredential
  ) external requiresAuth isValidCredential(_signedCredential) {
    if (_poolIDs.length != _amounts.length) {
      revert InvalidParams(
        msg.sender,
        address(this),
        msg.sig,
        "Pool IDs and amounts must be same length"
      );
    }
    require(_poolIDs.length == _amounts.length, "Pool IDs and amounts must be same length");

    uint256 total = 0;

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      total += _amounts[i];
    }

    _poolFundsInWFIL(total);

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      GetRoute.pool(router, _poolIDs[i]).makePayment(
        address(this),
        _amounts[i]
      );
    }
  }

  function stakeToMakePayments(
    uint256[] calldata _poolIDs,
    uint256[] calldata _amounts,
    uint256[] calldata _powerTokenTokenAmounts,
    SignedCredential memory _signedCredential
  ) external requiresAuth isValidCredential(_signedCredential) {
    if (_poolIDs.length != _amounts.length || _poolIDs.length != _powerTokenTokenAmounts.length) {
      revert InvalidParams(
        msg.sender,
        address(this),
        msg.sig,
        "Pool IDs, amounts, and power token amounts must be same length"
      );
    }

    for (uint256 i = 0; i < _poolIDs.length; i++) {
      GetRoute.pool(router, _poolIDs[i]).stakeToPay(
        _amounts[i], _signedCredential, _powerTokenTokenAmounts[i]
      );
    }
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  function _checkRemoveMiner(
    VerifiableCredential memory agentCred,
    VerifiableCredential memory minerCred
  ) internal view returns (bool) {
    // if nothing is borrowed, can remove
    if (totalPowerTokensStaked() == 0) {
      return true;
    }

    uint256 maxWithdrawAmt = _maxWithdraw(agentCred);
    uint256 minerLiquidationValue = _liquidationValue(
      minerCred.miner.assets,
      minerCred.miner.liabilities,
      0
    );

    _canRemovePower(agentCred.miner.qaPower, minerCred.miner.qaPower);

    if (maxWithdrawAmt <= minerLiquidationValue) {
      revert InsufficientCollateral(
        address(this),
        msg.sender,
        minerLiquidationValue,
        maxWithdrawAmt,
        msg.sig,
        "Agent does not have enough collateral to remove Miner"
      );
    }

    return true;
  }

  function _canAddMiner(address miner) internal view returns (bool) {
    // check to make sure pending owner is address(this);
    require(IMockMiner(miner).next_owner(miner) == address(this), "Agent must be set as the nextOwner on the miner");
    // check to make sure no beneficiary address (or that we were set as the beneficiary address)
    require(IMockMiner(miner).get_beneficiary(miner) == address(0) || IMockMiner(miner).get_beneficiary(miner) == address(this));

    return true;
  }

  function _changeMinerOwner(address miner, address owner) internal {
    IMockMiner(miner).change_owner_address(miner, owner);
  }

  function _addMiner(address miner) internal {
    // Confirm the miner is valid and can be added
    require(_canAddMiner(miner), "Cannot add miner unless it is set as the nextOwner on the miner and no beneficiary address is set");

    _changeMinerOwner(miner, address(this));

    GetRoute.minerRegistry(router).addMiner(miner);
  }

  function _pullFundsFromMiner(address miner, uint256 amount) internal {
    require(
      IMinerRegistry(GetRoute.minerRegistry(router)).minerRegistered(id, miner),
      "Agent does not own miner"
    );

    uint256 withdrawAmount = amount;
    if (withdrawAmount == 0) {
      // withdraw all if amount is 0
      withdrawAmount = miner.balance;
    }

    IMockMiner(miner).withdrawBalance(withdrawAmount);
  }

  function _pushFundsToMiner(address miner, uint256 amount) internal {
    (bool success, ) = miner.call{value: amount}("");
    require(success, "Failed to send funds to miner");
  }

  // ensures theres enough native FIL bal in the agent to push funds to miners
  function _poolFundsInFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;
    IERC20 wFIL20 = GetRoute.wFIL20(router);
    uint256 wFILBal = wFIL20.balanceOf(address(this));

    if (filBal >= amount) {
      return;
    }

    require(filBal + wFILBal >= amount, "Not enough FIL or wFIL to push to miner");

    IWFIL(address(wFIL20)).withdraw(amount - filBal);
  }

  // ensures theres enough wFIL bal in the agent to make payments to pools
  function _poolFundsInWFIL(uint256 amount) internal {
    uint256 filBal = address(this).balance;
    IERC20 wFIL20 = GetRoute.wFIL20(router);
    uint256 wFILBal = wFIL20.balanceOf(address(this));

    if (wFILBal >= amount) {
      return;
    }

    require(filBal + wFILBal >= amount, "Not enough FIL or wFIL to push to miner");

    IWFIL(address(wFIL20)).deposit{value: amount - wFILBal}();
  }

  function _burnPower(uint256 amount) internal returns (uint256) {
    IERC20 powerToken = GetRoute.powerToken20(router);
    // check
    require(amount <= powerToken.balanceOf(address(this)), "Agent: Cannot burn more power than the agent holds");
    // interact
    IPowerToken(address(powerToken)).burn(amount);

    return amount;
  }

  function _canCall() internal view returns (bool) {
    return AuthController.canCallSubAuthority(router, address(this));
  }

  function _requiresAuth() internal view {
    require(_canCall(), "Agent: Not authorized");
  }

  function _requiresAuthOrPolice() internal view {
    require(_canCall() || IRouter(router).getRoute(ROUTE_AGENT_POLICE) == (msg.sender), "Agent: Not authorized");
  }

  function _notOverPowered() internal view {
    if (GetRoute.agentPolice(router).isOverPowered(id)) {
      revert OverPowered(id, "Agent: Cannot perform action while overpowered");
    }
  }

  function _notOverLeveraged() internal view {
    if (GetRoute.agentPolice(router).isOverLeveraged(id)) {
      revert OverLeveraged(id, "Agent: Cannot perform action while overleveraged");
    }
  }

  function _notInDefault() internal view {
    if (GetRoute.agentPolice(router).isInDefault(id)) {
      revert InDefault(id, "Agent: Cannot perform action while in default");
    }
  }

  function _isValidCredential(
    address agent,
    SignedCredential memory signedCredential
  ) internal view returns (bool) {
    return GetRoute.agentPolice(router).isValidCredential(agent, signedCredential);
  }

  // TODO: should we add any EDR for some number of days to this?
  // thinking no... because assets can include this amount server side to give us more flexibility and cheaper gas
  function _maxWithdraw(VerifiableCredential memory vc) internal view returns (uint256) {
    uint256 liquid = liquidAssets();

    // if nothing is borrowed, you can withdraw everything
    if (totalPowerTokensStaked() == 0) {
      return liquid;
    }

    uint256 liquidationValue = _liquidationValue(vc.miner.assets, vc.miner.liabilities, liquid);
    uint256 minCollateral = _minCollateral(vc);

    if (liquidationValue > minCollateral) {
      // dont report a maxWithdraw that the Agent can't currently afford..
      return Math.min(liquidationValue - minCollateral, liquid);
    }

    return 0;
  }

  function _minCollateral(
    VerifiableCredential memory vc
  ) internal view returns (uint256 minCollateral) {
    uint256[] memory poolIDs = _getStakedPoolIDs();

    for (uint256 i = 0; i < poolIDs.length; ++i) {
      uint256 poolID = poolIDs[i];
      minCollateral += GetRoute
        .pool(router, poolID)
        .implementation()
        .minCollateral(
          IRouter(router).getAccount(id, poolID),
          vc
        );
    }
  }

  /// @dev ensure we don't remove too much power
  function _canRemovePower(uint256 totalPower, uint256 powerToRemove) internal view {
      // ensure that the power we're removing by removing a miner does not put us into an "overPowered" state
      if (totalPower < powerToRemove + GetRoute.powerToken(router).powerTokensMinted(id)) {
        revert InsufficientCollateral(
          address(this),
          msg.sender,
          powerToRemove,
          // TODO: here we should do totalPower - powMinted, but that could underflow..
          0,
          msg.sig,
          "Attempted to remove a miner with too much power"
        );
      }
  }

  function _getStakedPoolIDs() internal view returns (uint256[] memory) {
    return GetRoute.agentPolice(router).poolIDs(id);
  }

  function _liquidationValue(
    uint256 assets,
    uint256 liabilities,
    uint256 liquid
  ) internal pure returns (uint256) {
    uint256 recoverableAssets = assets + liquid;
    if (recoverableAssets < liabilities) {
      return 0;
    }
    return recoverableAssets - liabilities;
  }

  function _withdrawBalance(address receiver, uint256 amount) internal {
    _poolFundsInFIL(amount);

    (bool success,) = receiver.call{value: amount}("");
    require(success, "Withdrawal failed.");

    emit WithdrawBalance(receiver, amount);
  }
}

