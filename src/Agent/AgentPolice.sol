// SPDX-License-Identifier: BUSL-1.1
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
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {SignedCredential, Credentials, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {EPOCHS_IN_DAY,EPOCHS_IN_WEEK} from "src/Constants/Epochs.sol";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable {

  using AccountHelpers for Account;
  using FixedPointMathLib for uint256;
  using Credentials for VerifiableCredential;
  using FilAddress for address;

  error AgentStateRejected();
  error OverLimitDTI();
  error OverLimitDTE();
  error OverLimitDTL();
  error OverFaultySectorLimit();
  error PayUp();

  event CredentialUsed(uint256 indexed agentID, VerifiableCredential vc);

  IWFIL internal wFIL;

  /// @notice `POOL_ADDRESS` is the address of the single pool for GLIF, this is a temporary solution until we completely get rid of multipool architecture
  address public POOL_ADDRESS;

  /// @notice `defaultWindow` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is in default
  uint256 public defaultWindow;

  /// @notice `administrationWindow` is the number of `epochsPaid` from `block.number` that determines if an Agent's account is eligible for administration
  uint256 public administrationWindow;

  /// @notice `maxDTE` is the maximum amount of principal to equity ratio before withdrawals are prohibited
  /// NOTE this is separate DTE for withdrawing than any DTE that the Infinity Pool relies on
  /// This variable is populated on deployment and can be updated to match the rate module using an admin func
  uint256 public maxDTE = 0;

  /// @notice `maxDTL` is the maximum amount of principal to collateral value ratio before withdrawals are prohibited
  /// NOTE this is separate DTL for withdrawing than any DTL that the Infinity Pool relies on
  /// This variable is populated on deployment and can be updated to match the rate module using an admin func
  uint256 public maxDTL = 0;

  /// @notice `DTLLiquidationThreshold` is the DTL ratio threshold at which an agent is liquidated
  /// initially set at 90%, so if the agent is >90% DTL, it is elligible for liquidation
  uint256 public DTLLiquidationThreshold = 9e17;

  /// @notice `maxDTI` is the maximum amount of debt to income ratio before withdrawals are prohibited
  /// NOTE this is separate DTI for withdrawing than any DTI that the Infinity Pool relies on
  /// This variable is populated on deployment and can be updated to match the rate module using an admin func
  uint256 public maxDTI = 0;

  /// @notice `maxConsecutiveFaultEpochs` is the number of epochs of consecutive faults that are required in order to put an agent on administration or into default
  uint256 public maxConsecutiveFaultEpochs = 3 * EPOCHS_IN_DAY;

  /// @dev `maxEpochsOwedTolerance` - an agent's account must be paid up within this epoch buffer in order to borrow again
  uint256 public maxEpochsOwedTolerance = EPOCHS_IN_DAY * 1;

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
    address _router,
    address _pool,
    IWFIL _wFIL
  ) VCVerifier(_name, _version, _router) Operatable(_owner, _operator) {
    defaultWindow = _defaultWindow;
    administrationWindow = EPOCHS_IN_WEEK;
    // set the DTI, DTE, and DTL ratios to match the pool on deployment if a pool is passed
    // if no pool is passed, you can update these values using the admin function matchRiskParams
    if (_pool != address(0)) {
      IRateModule rm = IPool(_pool).rateModule();
      maxDTE = rm.maxDTE();
      maxDTI = rm.maxDTI();
      // confusing name: LTV == DTL, this is a variable rename
      maxDTL = rm.maxLTV();
    }

    POOL_ADDRESS = _pool;
    wFIL = _wFIL;
  }

  modifier onlyAgent() {
    AuthController.onlyAgent(router, msg.sender);
    _;
  }

  modifier onlyWhenBehindTargetEpoch(address agent, uint256 lookback) {
    if (!_epochsPaidBehindTarget(IAgent(agent).id(), lookback)) {
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
    _agentApproved(vc, _getAccount(vc.subject));
  }

  /**
   * @notice `setAgentDefaulted` puts the agent in default permanently
   * @param agent The address of the agent to put in default
   */
  function setAgentDefaulted(address agent) external onlyOwner onlyWhenBehindTargetEpoch(agent, defaultWindow) {
    IAgent(agent).setInDefault();
    emit Defaulted(agent);
  }

  /**
   * @notice `agentLiquidated` checks if the agent has been liquidated
   * @param agentID The address of the agent to check
   */
  function agentLiquidated(uint256 agentID) public view returns (bool) {
    Account memory account = _getAccount(agentID);
    // if the Agent is not actively borrowing from the pool, they are not liquidated
    // TODO: is this check necessary?
    if (account.principal == 0 && account.startEpoch == 0) return false;
    return account.defaulted;
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
    onlyWhenBehindTargetEpoch(agent, administrationWindow)
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
   * @dev DEPRECATED: use setAgentDefaultDTL instead
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
   * @notice `setAgentDefaultDTL` puts the agent in default if the DTL ratio is above the threshold
   * @param agent The address of the agent to put in default
   * @param vc The VerifiableCredential of the agent
   */
  function setAgentDefaultDTL(address agent, VerifiableCredential calldata vc) external onlyOwner {
    Account memory account = _getAccount(vc.subject);
    // compute the interest owed on the principal to add to principal to get total debt
    uint256 rate = IPool(POOL_ADDRESS).getRate(vc);
    uint256 debt = account.principal + _interestOwed(account, rate);

    if (debt.divWadDown(vc.getCollateralValue(address(GetRoute.credParser(router)))) < DTLLiquidationThreshold) {
      revert Unauthorized();
    }

    IAgent(agent).setInDefault();
    emit Defaulted(agent);
  }

  /**
   * @notice `prepareMinerForLiquidation` changes the owner address of `miner` on `agent` to be `owner` of Agent Police
   * @param agent The address of the agent to set the state of
   * @param miner The ID of the miner to change owner to liquidator
   * @param liquidator The ID of the liquidator
   * @dev After calling this function and the liquidation completes, call `liquidatedAgent` next to proceed with the liquidation
   */
  function prepareMinerForLiquidation(
    address agent,
    uint64 miner,
    uint64 liquidator
  ) external onlyOwner {
    IAgent(agent).prepareMinerForLiquidation(miner, liquidator);
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
    // transfer the assets into the agent police
    wFIL.transferFrom(msg.sender, address(this), amount);
    uint256 excessAmount = _writeOffPools(agentID, amount);

    // transfer the excess assets to the Agent's owner
    wFIL.transfer(IAuth(agent).owner(), excessAmount);
  }

  /**
  * @notice setMaxEpochsOwedTolerance sets epochsPaidBorrowBuffer in storage
  * @param _maxEpochsOwedTolerance The new value for maxEpochsOwedTolerance
  */
  function setMaxEpochsOwedTolerance(uint256 _maxEpochsOwedTolerance) external onlyOwner {
    // if maxEpochsOwedTolerance is greater than 1 day, Agents can over pay interest
    if (_maxEpochsOwedTolerance > EPOCHS_IN_DAY) revert InvalidParams();

    maxEpochsOwedTolerance = _maxEpochsOwedTolerance;
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
    if (credentialUsed(sc.vc)) revert InvalidCredential();
  }

  /**
   * @notice `credentialUsed` returns true if the credential has been used before
   */
  function credentialUsed(VerifiableCredential calldata vc) public view returns (bool) {
    return _credentialUseBlock[digest(vc)] > 0;
  }

  /**
   * @notice registerCredentialUseBlock burns a credential by storing a hash of its signature
   * @dev only an Agent can burn its own credential
   */
  function registerCredentialUseBlock(
    SignedCredential memory sc
  ) external onlyAgent {
    if (IAgent(msg.sender).id() != sc.vc.subject) revert Unauthorized();
    _credentialUseBlock[digest(sc.vc)] = block.number;

    emit CredentialUsed(sc.vc.subject, sc.vc);
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
    Account memory account = _getAccount(vc.subject);
    // check to ensure we can withdraw equity from this pool
    _agentApproved(vc, account);
    // check to ensure the withdrawal does not bring us over maxDTE, maxDTI, or maxDTL
    address credParser = address(GetRoute.credParser(router));
    // check to make sure the after the withdrawal, the DTE, DTI, DTL are all within the acceptable range
    uint256 principal = account.principal;
    // nothing borrowed, good to go!
    if (principal == 0) return;

    uint256 agentTotalValue = vc.getAgentValue(credParser);
    // since agentTotalValue includes borrowed funds (principal),
    // agentTotalValue should always be greater than principal
    if (agentTotalValue <= principal) revert OverLimitDTE();

    // compute the interest owed on the principal to add to principal to get total debt
    uint256 rate = IPool(POOL_ADDRESS).getRate(vc);
    uint256 debt = principal + _interestOwed(account, rate);
    // if the DTE is greater than maxDTE, revert
    if (debt.divWadDown(agentTotalValue - debt) > maxDTE) revert OverLimitDTE();
    // if the DTL is greater than maxDTL, revert
    if (_computeDTL(account, vc, credParser, rate) > maxDTL) revert OverLimitDTL();
    // if the DTI is greater than maxDTI, revert
    uint256 dailyRate = account.principal.mulWadUp(rate).mulWadUp(EPOCHS_IN_DAY);
    if (dailyRate.divWadUp(vc.getExpectedDailyRewards(credParser)) > maxDTI) revert OverLimitDTI();
  }

  /**
   * @notice `confirmRmAdministration` checks to ensure an Agent's faulty sectors are in the tolerance range, and they're within the payment tolerance window
   * @param vc the verifiable credential
   */
  function confirmRmAdministration(VerifiableCredential calldata vc) external view {
    if (_epochsPaidBehindTarget(vc.subject, administrationWindow)) revert AgentStateRejected();

    address credParser = address(GetRoute.credParser(router));
    // if were above the DTL ratio, revert
    if (_computeDTL(_getAccount(vc.subject), vc, credParser, IPool(POOL_ADDRESS).getRate(vc)) > maxDTL) revert AgentStateRejected();

    if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
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
   * @notice `setAdministrationWindow` changes the administration window epochs
   */
  function setAdministrationWindow(uint256 _administrationWindow) external onlyOwner {
    administrationWindow = _administrationWindow;
  }

  /**
   * @notice `setMaxDTE` sets the maximum DTE for withdrawals and removing miners
   */
  function setMaxDTE(uint256 _maxDTE) external onlyOwner {
    maxDTE = _maxDTE;
  }

  /**
   * @notice `setMaxDTL` sets the maximum DTL for withdrawals and removing miners
   */
  function setMaxDTL(uint256 _maxDTL) external onlyOwner {
    maxDTL = _maxDTL;
  }

  /**
   * @notice `setDTLLiquidationThreshold` sets the DTL ratio at which an agent can be liquidated
   */
  function setDTLLiquidationThreshold(uint256 _DTLLiquidationThreshold) external onlyOwner {
    DTLLiquidationThreshold = _DTLLiquidationThreshold;
  }

  /**
   * @notice `setMaxDTI` sets the maximum DTI for withdrawals and removing miners
   */
  function setMaxDTI(uint256 _maxDTI) external onlyOwner {
    maxDTI = _maxDTI;
  }

  /**
   * @notice `setRiskParamsToMatchPool` is a convenience method for setting the risk parameters of the agent police to match the pool's rate module
   */
  function setRiskParamsToMatchPool() external onlyOwner {
    IRateModule rm = IPool(POOL_ADDRESS).rateModule();
    maxDTE = rm.maxDTE();
    maxDTI = rm.maxDTI();
    maxDTL = rm.maxLTV();
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

  /**
   * @notice `setSectorFaultyTolerancePercent` sets the percentage of sectors that can be faulty before the agent is considered faulty
   */
  function setPoolAddress(address _pool) external onlyOwner {
    POOL_ADDRESS = _pool;
  }

  function refreshRoutes() external {
    wFIL = GetRoute.wFIL(router);
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  /// @dev computes the pro-rata split of a total amount based on principal
  function _writeOffPools(
    uint256 _agentID,
    uint256 _recoveredAmount
  ) internal returns (uint256 excessFunds) {
    wFIL.approve(POOL_ADDRESS, _recoveredAmount);
    // write off the pool's assets
    uint256 totalOwed = IPool(POOL_ADDRESS).writeOff(_agentID, _recoveredAmount);
    return _recoveredAmount > totalOwed ? _recoveredAmount - totalOwed : 0;
  }

  /// @dev returns true if any pool has an `epochsPaid` behind `targetEpoch` (and thus is underpaid)
  function _epochsPaidBehindTarget(
    uint256 _agentID,
    uint256 _targetEpoch
  ) internal view returns (bool) {
    return _getAccount(_agentID).epochsPaid < block.number - _targetEpoch;
  }

  /// @dev returns true if the Agent has 
  function _consecutiveFaultyEpochsExceeded(address _agent) internal view returns (bool) {
    uint256 faultyStart = IAgent(_agent).faultySectorStartEpoch();
    // if the agent is not faulty, return false
    if (faultyStart == 0) return false;

    // must be faulty for maxConsecutiveFaultEpochs epochs before taking action
    return block.number >= faultyStart + maxConsecutiveFaultEpochs;
  }

  /// @dev loops through the pools and calls isApproved on each, 
  /// reverting in the case of any non-approvals,
  /// or in the case that an account owes payments over the acceptable threshold
  function _agentApproved(VerifiableCredential calldata vc, Account memory account) internal view {
    if (!IPool(POOL_ADDRESS).isApproved(account, vc)) revert AgentStateRejected();
    // ensure the account's epochsPaid is at most maxEpochsOwedTolerance behind the current epoch height
    // this is to prevent the agent from doing an action before paying up
    if (account.epochsPaid + maxEpochsOwedTolerance < block.number) revert PayUp();
    // check faulty sector limit
    address credParser = address(GetRoute.credParser(router));
    if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
  }

  /// @dev returns the account of the agent
  /// @param agentID the ID of the agent
  /// @return the account of the agent
  /// @dev the pool ID is hardcoded to 0, as this is a relic of our obsolete multipool architecture
  function _getAccount(uint256 agentID) internal view returns (Account memory) {
    return AccountHelpers.getAccount(router, agentID, 0);
  }

  /// @dev returns the interest owed of a particular Account struct given a VerifiableCredential
  function _interestOwed(Account memory account, uint256 rate) internal view returns (uint256) {
    // compute the number of epochs that are owed to get current
    uint256 epochsToPay = block.number - account.epochsPaid;
    // multiply the rate by the principal to get the per epoch interest rate
    // the interestPerEpoch has an extra WAD to maintain precision
    uint256 interestPerEpoch = account.principal.mulWadUp(rate);
    // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
    // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
    return interestPerEpoch.mulWadUp(epochsToPay);
  }
  
  function _computeDTL(Account memory account, VerifiableCredential calldata vc, address credParser, uint256 rate) internal view returns (uint256) {
    // compute the interest owed on the principal to add to principal to get total debt
    uint256 debt = account.principal + _interestOwed(account, rate);
    // confusing naming convention - "collateral value" == "liquidation value" in this context
    uint256 liquidationValue = vc.getCollateralValue(credParser);
    // if there is no debt, DTL is 0
    if (debt == 0) return 0;
    // if liquidation value is 0 (and there is debt), we return the max uint256 value to avoid dividing by 0
    if (liquidationValue == 0) return type(uint256).max;
    // if liquidation value is 0 and there is no debt, the DTL ratio is also 0
    return debt.divWadDown(vc.getCollateralValue(credParser));
  }

  /**
   * @notice `faultySectorsExceeded` checks to ensure an agent has not exceeded the faulty sector tolerance
   * @return true if the agent has exceeded the faulty sector tolerance
   * TODO: review this faulty sector logic - is it possible to have faulty sectors and no live sectors? if not, we can simplify here
   */
  function _faultySectorsExceeded(VerifiableCredential memory vc, address credParser) internal view returns (bool) {
    // check to ensure the agent does not have too many faulty sectors
    uint256 faultySectors = vc.getFaultySectors(credParser);
    uint256 liveSectors = vc.getLiveSectors(credParser);
    // if we have no sectors, we're good to go
    if (liveSectors == 0 && faultySectors == 0) return false;
    // if we have no live sectors, but we have faulty sectors, we exceeded the limit
    if (liveSectors == 0 && faultySectors > 0) return true;
    // if were above the faulty sector ratio, we exceeded the limit
    if (
      vc.getFaultySectors(credParser).divWadDown(vc.getLiveSectors(credParser)) > sectorFaultyTolerancePercent
    ) return true;

    return false;
  }
}
