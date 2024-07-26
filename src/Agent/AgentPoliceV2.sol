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


contract AgentPoliceV2 is IAgentPolice, VCVerifier, Operatable, Pausable {
    using AccountHelpers for Account;
    using FixedPointMathLib for uint256;
    using Credentials for VerifiableCredential;
    using FilAddress for address;

    event CredentialUsed(uint256 indexed agentID, VerifiableCredential vc);

    IWFIL internal immutable _wFIL;
    IMinerRegistry internal immutable _minerRegistry;

    /// @notice `borrowDTL` is the maximum amount of debt to collateral value ratio before the agent's borrows and withdrawals are halted
    /// initially set at 75%, so if the agent is >75% DTL, it cannot borrow or withdraw
    uint256 public borrowDTL;

    /// @notice `liquidationDTL` is the DTL ratio threshold at which an agent is liquidated
    /// initially set at 85%, so if the agent is >85% DTL, it is elligible for liquidation
    uint256 public liquidationDTL;

    /// @notice `sectorFaultyTolerancePercent` is the percentage of sectors that can be faulty before an agent is considered in a faulty state. 1e18 = 100%
    uint256 public sectorFaultyTolerancePercent = 1e15;

    /// @notice `liquidationFee` is the fee charged to liquidate an agent, only charged if LPs are made whole first
    uint256 public liquidationFee = 1e17;

    /// @notice `maxMiners` is the maximum number of miners an agent can have
    uint32 public maxMiners = 50;

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
        // 75%
        borrowDTL = 75e16;
        // 85%
        liquidationDTL = 85e16;

        _wFIL = IWFIL(IRouter(_router).getRoute(ROUTE_WFIL_TOKEN));
        _minerRegistry = GetRoute.minerRegistry(router);
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
    function agentApproved(VerifiableCredential calldata vc) external {
        _agentApproved(msg.sender, vc, _getAccount(vc.subject), _pool(), 0);
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
        if (dtl < borrowDTL) revert Unauthorized();

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
        if (dtl < liquidationDTL) revert Unauthorized();

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

        if (credentialUsed(sc.vc) > 0) revert InvalidCredential();

        // due to current restrictions in Agent.sol, we have to enforce the max miners per agent here
        // this is a temporary solution until we upgrade the agent
        if (action == IAgent.addMiner.selector && _minerRegistry.minersCount(agent) > maxMiners) {
            revert MaxMinersReached();
        }
    }

    /**
     * @notice `credentialUsed` returns true if the credential has been used before
     */
    function credentialUsed(VerifiableCredential calldata vc) public view returns (uint256) {
        return _credentialUseBlock[digest(vc)];
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
        // if the vc.value is > 0, this is a withdrawal amount, so the removingEquity param just uses the value passed in the cred
        if (vc.value > 0) {
            _agentApproved(msg.sender, vc, account, pool, vc.value);
        } else if (vc.target > 0) {
            _agentApproved(msg.sender, vc, account, pool, _getBuiltInActorBal(vc.target));
        } else {
            // if the confirmRmEquity call does not have a value or a target (miner) to remove, it's invalid
            revert InvalidCredential();
        }
    }

    /**
     * @notice `confirmRmAdministration` checks to ensure an Agent's DTL is in good standing and the agent's faulty sectors are in the tolerance range before removing the agent from administration
     * @param vc the verifiable credential
     */
    function confirmRmAdministration(VerifiableCredential calldata vc) external view {
        address credParser = address(GetRoute.credParser(router));
        (uint256 dtl,,) = FinMath.computeDTL(_getAccount(vc.subject), vc, _pool().getRate(), credParser);
        // if were above the DTL ratio, revert
        if (dtl > borrowDTL) revert AgentStateRejected();
        // if were above faulty sector limit, revert
        if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
    }

    /*//////////////////////////////////////////////
                  ADMIN CONTROLS
    //////////////////////////////////////////////*/

    /**
     * @notice `setborrowDTL` sets the maximum DTL for withdrawals and removing miners
     */
    function setBorrowDTL(uint256 _borrowDTL) external onlyOwner {
        borrowDTL = _borrowDTL;
    }

    /**
     * @notice `setliquidationDTL` sets the DTL ratio at which an agent can be liquidated
     */
    function setLiquidationDTL(uint256 _liquidationDTL) external onlyOwner {
        liquidationDTL = _liquidationDTL;
    }

    /**
     * @notice `setLiquidationFee` sets the liquidation fee charged on liquidations
     */
    function setLiquidationFee(uint256 _liquidationFee) external onlyOwner {
        liquidationFee = _liquidationFee;
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
     * @notice sets the maximum number of miners an agent can have
     */
    function setMaxMiners(uint32 _maxMiners) external onlyOwnerOperator {
        maxMiners = _maxMiners;
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

    /// @dev checks to ensure the agent is in a healthy state
    /// reverting in the case of any non-approvals,
    /// or in the case that an account owes payments over the acceptable threshold
    function _agentApproved(
        address agent,
        VerifiableCredential calldata vc,
        Account memory account,
        IPool pool,
        uint256 removingEquity
    ) internal view {
        // make sure the agent police isn't paused
        _requireNotPaused();
        address credParser = address(GetRoute.credParser(router));
        uint256 principal = account.principal;
        // nothing borrowed, good to go!
        if (principal == 0) return;

        (uint256 dtl, uint256 debt, uint256 liquidationValue) =
            FinMath.computeDTL(account, vc, pool.getRate(), credParser);

        // here we check to ensure the liquidationValue is under the total balance of the agent and all its miners
        // this is an extra security check that ensures, in the event the ADO is hijacked, that any loss of funds is minimized by the amount of balance actually held on miners + agent
        _assertLiquidationValueLTETotalValue(agent, vc.subject, liquidationValue, removingEquity);

        // if the DTL is greater than borrowDTL, revert
        if (dtl > borrowDTL) revert OverLimitDTL();
        // check faulty sector limit
        if (_faultySectorsExceeded(vc, credParser)) revert OverFaultySectorLimit();
        // check if accrued debt has exceeded this agent's quota level
        if (debt > levels[accountLevel[vc.subject]]) revert OverLimitQuota();
    }

    /// @dev throws an error if the liquidation value is greater than the total balance of the agent and all its miners
    /// @dev the loop is capped at the maxMiners constant to prevent gas exhaustion
    /// @param agent the address of the agent
    /// @param agentID the ID of the agent
    /// @param liquidationValue the liquidation value of the agent as reported by the VC _after_ the event has taken place
    /// @param removingEquity the amount of equity being removed from the agent in the event of a withdrawal or remove miner
    function _assertLiquidationValueLTETotalValue(
        address agent,
        uint256 agentID,
        uint256 liquidationValue,
        uint256 removingEquity
    ) internal view {
        // first get the liquid FIL on the agent
        uint256 liquidFIL = _wFIL.balanceOf(agent) + agent.balance;
        // next get the balance from all the agent's miners
        uint256 totalBal = 0;
        uint256 minerCount = _minerRegistry.minersCount(agentID);
        for (uint256 i = 0; i < minerCount; i++) {
            // here since builtin miners are using ID address, we need to convert to the EVM address type
            totalBal += _getBuiltInActorBal(_minerRegistry.getMiner(agentID, i));
        }
        // if the liquidation value is greater than the total balance of the agent + miners, revert
        // here we remove the amount of equity being removed from the agent to ensure that we're matching a post-action state (within the credential) against the post-action balance (computed on chain)
        if (liquidationValue + removingEquity > liquidFIL + totalBal) revert LiquidationValueTooHigh();
    }

    /// @dev returns the account of the agent
    /// @param agentID the ID of the agent
    /// @return the account of the agent
    /// @dev the pool ID is hardcoded to 0, as this is a relic of our obsolete multipool architecture
    function _getAccount(uint256 agentID) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agentID, 0);
    }

    /// @dev returns the balance of a built-in actor
    function _getBuiltInActorBal(uint64 target) internal view returns (uint256) {
        return address(bytes20(abi.encodePacked(hex"ff0000000000000000000000", target))).balance;
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
