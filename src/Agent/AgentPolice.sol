// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {FinMath} from "src/Pool/FinMath.sol";
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
import {EPOCHS_IN_DAY, EPOCHS_IN_WEEK} from "src/Constants/Epochs.sol";
import {ROUTE_INFINITY_POOL, ROUTE_WFIL_TOKEN} from "src/Constants/Routes.sol";

contract AgentPolice is IAgentPolice, VCVerifier, Operatable, Pausable {
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;
    using Credentials for VerifiableCredential;
    using FilAddress for address;

    error AgentStateRejected();
    error OverLimitDTI();
    error OverLimitDTE();
    error OverLimitDTL();
    error OverLimitQuota();
    error OverFaultySectorLimit();

    event CredentialUsed(uint256 indexed agentID, VerifiableCredential vc);

    IWFIL internal immutable _wFIL;

    /// @notice `maxDTE` is the maximum amount of principal to equity ratio before withdrawals are prohibited
    /// NOTE this is separate DTE for withdrawing than any DTE that the Infinity Pool relies on
    /// This variable is populated on deployment and can be updated to match the rate module using an admin func
    uint256 public maxDTE;

    /// @notice `maxDTL` is the maximum amount of principal to collateral value ratio before withdrawals are prohibited
    /// NOTE this is separate DTL for withdrawing than any DTL that the Infinity Pool relies on
    /// This variable is populated on deployment and can be updated to match the rate module using an admin func
    uint256 public maxDTL;

    /// @notice `dtlLiquidationThreshold` is the DTL ratio threshold at which an agent is liquidated
    /// initially set at 85%, so if the agent is >85% DTL, it is elligible for liquidation
    uint256 public dtlLiquidationThreshold;

    /// @notice `maxDTI` is the maximum amount of debt to income ratio before withdrawals are prohibited
    /// NOTE this is separate DTI for withdrawing than any DTI that the Infinity Pool relies on
    /// This variable is populated on deployment and can be updated to match the rate module using an admin func
    uint256 public maxDTI;

    /// @notice `sectorFaultyTolerancePercent` is the percentage of sectors that can be faulty before an agent is considered in a faulty state. 1e18 = 100%
    uint256 public sectorFaultyTolerancePercent = 1e15;

    /// @notice `liquidationFee` is the fee charged to liquidate an agent, only charged if LPs are made whole first
    uint256 public liquidationFee = 1e17;

    /// @notice `_credentialUseBlock` maps a credential's hash to when it was used
    mapping(bytes32 => uint256) private _credentialUseBlock;

    /// @notice `levels` is a leveling system that sets maximum borrow amounts on accounts
    uint256[10] public levels = [
        100_000e18,
        250_000e18,
        500_000e18,
        1_000_000e18,
        2_000_000e18,
        3_000_000e18,
        4_000_000e18,
        5_000_000e18,
        6_000_000e18,
        7_500_000e18
    ];

    /// @notice `accountLevel` is a mapping of agentID to level
    mapping(uint256 => uint256) public accountLevel;

    constructor(string memory _name, string memory _version, address _owner, address _operator, address _router)
        VCVerifier(_name, _version, _router)
        Operatable(_owner, _operator)
    {
        // default risk params:
        // dte => 300%
        maxDTE = 3e18;
        // dti => 80%
        maxDTI = 8e17;
        // dtl => 80%
        maxDTL = 8e17;
        // max dtl before liquidation => 85%
        dtlLiquidationThreshold = 85e16;

        _wFIL = IWFIL(IRouter(_router).getRoute(ROUTE_WFIL_TOKEN));
    }

    modifier onlyAgent() {
        AuthController.onlyAgent(router, msg.sender);
        _;
    }

    /*//////////////////////////////////////////////
                      CHECKERS
    //////////////////////////////////////////////*/

    /**
     * @notice `agentApproved` checks with each pool to see if the agent's position is approved and reverts if any pool returns false
     * @param vc the VerifiableCredential of the agent
     */
    function agentApproved(VerifiableCredential calldata vc) external view {
        _agentApproved(vc, _getAccount(vc.subject), _pool());
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
    function putAgentOnAdministration(address agent, SignedCredential calldata sc, address administration)
        external
        onlyOwner
    {
        // ensure the credential is valid
        validateCred(IAgent(agent).id(), msg.sig, sc);
        (uint256 dtl,,) = FinMath.computeDTL(
            _getAccount(sc.vc.subject), sc.vc, _pool().getRate(), address(GetRoute.credParser(router))
        );
        if (dtl < maxDTL) revert Unauthorized();

        IAgent(agent).setAdministration(administration.normalize());

        emit OnAdministration(agent);
    }

    /**
     * @notice `setAgentDefaultDTL` puts the agent in default if the DTL ratio is above the threshold
     * @param agent The address of the agent to put in default
     * @param sc a SignedCredential of the agent
     */
    function setAgentDefaultDTL(address agent, SignedCredential calldata sc) external onlyOwner {
        // ensure the credential is valid
        validateCred(IAgent(agent).id(), msg.sig, sc);
        (uint256 dtl,,) = FinMath.computeDTL(
            _getAccount(sc.vc.subject), sc.vc, _pool().getRate(), address(GetRoute.credParser(router))
        );
        if (dtl < dtlLiquidationThreshold) revert Unauthorized();

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
    function prepareMinerForLiquidation(address agent, uint64 miner, uint64 liquidator) external onlyOwner {
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
        _wFIL.transferFrom(msg.sender, address(this), amount);

        IPool pool = _pool();
        // approve the pool to spend the recovered funds
        _wFIL.approve(address(pool), amount);
        // handle the liquidation in the pool, transferring the amount of wFIL owed to the pool
        pool.writeOff(agentID, amount);

        // calculate the excess amount of wFIL that wasn't used in the liquidation
        uint256 excessAmount = _wFIL.balanceOf(address(this));
        // if there is any excess recovered funds.. to use transfer it to the Agent's owner
        if (excessAmount > 0) {
            // calculate how much FIL was needed to make LPs whole
            uint256 owedToPool = amount - excessAmount;

            // liquidation fee, based on interest + principal of agent's position in the pool
            uint256 liquidatorFee = owedToPool.mulWadDown(liquidationFee);

            if (excessAmount > liquidatorFee) {
                // transfer the liquidation fee to the treasury
                _wFIL.transfer(GetRoute.treasury(router), liquidatorFee);
                // transfer anything remaining to the agent's owner
                _wFIL.transfer(IAuth(agent).owner(), excessAmount - liquidatorFee);
            } else {
                // transfer a portion of the liquidation fee to the treasury
                _wFIL.transfer(GetRoute.treasury(router), excessAmount);
            }
        }
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
    function isValidCredential(uint256 agent, bytes4 action, SignedCredential calldata sc) external view {
        // reverts if the credential isn't valid
        validateCred(agent, action, sc);

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
     * @notice registerCredentialUseBlock burns a credential by storing a hash of the VC
     * @dev only an Agent can burn its own credential
     * @dev the computed digest includes a block number in it, so nonces are not necessary because only 1 valid credential can exist at one time
     */
    function registerCredentialUseBlock(SignedCredential memory sc) external onlyAgent {
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
    function confirmRmEquity(VerifiableCredential calldata vc) external view {
        Account memory account = _getAccount(vc.subject);
        IPool pool = _pool();
        // check to ensure we can withdraw equity from this pool
        _agentApproved(vc, account, pool);
    }

    /**
     * @notice `confirmRmAdministration` checks to ensure an Agent's DTL is in good standing and the agent's faulty sectors are in the tolerance range before removing the agent from administration
     * @param vc the verifiable credential
     */
    function confirmRmAdministration(VerifiableCredential calldata vc) external view {
        address credParser = address(GetRoute.credParser(router));
        (uint256 dtl,,) = FinMath.computeDTL(_getAccount(vc.subject), vc, _pool().getRate(), credParser);
        // if were above the DTL ratio, revert
        if (dtl > maxDTL) revert AgentStateRejected();
        // if were above faulty sector limit, revert
        if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
    }

    /*//////////////////////////////////////////////
                  ADMIN CONTROLS
    //////////////////////////////////////////////*/

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
     * @notice `setdtlLiquidationThreshold` sets the DTL ratio at which an agent can be liquidated
     */
    function setDtlLiquidationThreshold(uint256 _dtlLiquidationThreshold) external onlyOwner {
        dtlLiquidationThreshold = _dtlLiquidationThreshold;
    }

    /**
     * @notice `setLiquidationFee` sets the liquidation fee charged on liquidations
     */
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;
    }

    /**
     * @notice `setMaxDTI` sets the maximum DTI for withdrawals and removing miners
     */
    function setMaxDTI(uint256 _maxDTI) external onlyOwner {
        maxDTI = _maxDTI;
    }

    /**
     * @notice `pause` sets this contract paused
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice `unpause` resumes this contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice `setSectorFaultyTolerancePercent` sets the percentage of sectors that can be faulty before the agent is considered faulty
     */
    function setSectorFaultyTolerancePercent(uint256 _sectorFaultyTolerancePercent) external onlyOwner {
        sectorFaultyTolerancePercent = _sectorFaultyTolerancePercent;
    }

    /**
     * @notice sets the array of max borrow amounts for each level
     */
    function setLevels(uint256[10] calldata _levels) external onlyOwnerOperator {
        levels = _levels;
    }

    /**
     * @notice sets the array of max borrow amounts for each level
     */
    function setAgentLevels(uint256[] calldata agentIDs, uint256[] calldata level) external onlyOwner {
        if (agentIDs.length != level.length) revert InvalidParams();
        uint256 i = 0;
        for (; i < agentIDs.length; i++) {
            accountLevel[agentIDs[i]] = level[i];
        }
    }

    /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
    //////////////////////////////////////////////*/

    /// @dev loops through the pools and calls isApproved on each,
    /// reverting in the case of any non-approvals,
    /// or in the case that an account owes payments over the acceptable threshold
    function _agentApproved(VerifiableCredential calldata vc, Account memory account, IPool pool) internal view {
        // make sure the agent police isn't paused
        _requireNotPaused();
        // check to ensure the withdrawal does not bring us over maxDTE, maxDTI, or maxDTL
        address credParser = address(GetRoute.credParser(router));
        // check to make sure the after the withdrawal, the DTE, DTI, DTL are all within the acceptable range
        uint256 principal = account.principal;
        // nothing borrowed, good to go!
        if (principal == 0) return;

        uint256 rate = pool.getRate();
        (uint256 dte, uint256 debt,) = FinMath.computeDTE(account, vc, rate, credParser);
        (uint256 dti,,) = FinMath.computeDTI(account, vc, rate, credParser);
        (uint256 dtl,,) = FinMath.computeDTL(account, vc, rate, credParser);

        // compute the interest owed on the principal to add to principal to get total debt
        // if the DTE is greater than maxDTE, revert
        if (dte > maxDTE) revert OverLimitDTE();
        // if the DTL is greater than maxDTL, revert
        if (dtl > maxDTL) revert OverLimitDTL();
        // if the DTI is greater than maxDTI, revert
        if (dti > maxDTI) revert OverLimitDTI();
        // check faulty sector limit
        if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
        // check if accrued debt has exceeded this agent's quota level
        if (debt > levels[accountLevel[vc.subject]]) revert OverLimitQuota();
    }

    /// @dev returns the account of the agent
    /// @param agentID the ID of the agent
    /// @return the account of the agent
    /// @dev the pool ID is hardcoded to 0, as this is a relic of our obsolete multipool architecture
    function _getAccount(uint256 agentID) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agentID, 0);
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
        if (vc.getFaultySectors(credParser).divWadDown(vc.getLiveSectors(credParser)) > sectorFaultyTolerancePercent) {
            return true;
        }

        return false;
    }

    function _pool() internal view returns (IPool) {
        return IPool(IRouter(router).getRoute(ROUTE_INFINITY_POOL));
    }
}
