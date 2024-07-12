// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {GetRoute} from "src/Router/GetRoute.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {RewardAccrual} from "src/Types/Structs/RewardAccrual.sol";
import {FinMath, AccrualMath} from "src/Pool/FinMath.sol";

import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {ICredentials} from "src/Types/Interfaces/ICredentials.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {RateUpdate} from "src/Types/Structs/RateUpdate.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_DAY, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {ROUTE_WFIL_TOKEN} from "src/Constants/Routes.sol";

uint256 constant WAD = 1e18;

/**
 * @title InfinityPool
 * @author GLIF
 * @notice The InfinityPool contract is an ERC4626 vault for FIL. It primarily handles depositing, borrowing, and paying FIL.
 * @dev the InfinityPool has some hooks and light integrations with the Offramp. The Offramp will not be enabled during launch.
 */
contract InfinityPoolV2 is IPool, Ownable, Pausable {
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FilAddress for address;
    using FilAddress for address payable;
    using FixedPointMathLib for uint256;
    using AccrualMath for RewardAccrual;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev cache the routes for gas efficiency
    address internal immutable _router;
    IAgentFactory internal _agentFactory;

    /// @dev `id` is a cache of the Pool's ID for gas efficiency
    uint256 public immutable id;

    /// @dev `asset` is the token that is being borrowed in the pool (WFIL)
    IERC20 public immutable asset;

    /// @dev `liquidStakingToken` is the token that represents a liquidStakingToken in the pool
    IPoolToken public immutable liquidStakingToken;

    /// @dev `lm` is the LiquidityMineSP contract that is responsible for distributing rewards to Agents on payments
    ILiquidityMineSP public lm;

    address public credParser;

    /// @dev `treasuryFeeRate` is the % of FIL charged to Agents on a per epoch basis (1e18 == 100%)
    uint256 public treasuryFeeRate = 1e17;

    /// @dev `totalBorrowed` is the total amount borrowed in this pool
    uint256 public totalBorrowed = 0;

    /// @dev `minimumLiquidity` is the percentage of total assets that should be reserved for exits
    uint256 public minimumLiquidity = 0;

    /// @dev `lastAccountingUpdateEpoch` is the epoch at which the pool's accounting was last updated
    uint256 public lastAccountingUpdateEpoch = 0;

    /// @dev `isShuttingDown` is a boolean that, when true, halts deposits and borrows. Once set, it cannot be unset.
    bool public isShuttingDown = false;

    /// @dev `rentalFeesOwedPerEpoch` is the % of FIL charged to Agents on a per epoch basis
    /// @dev this param uses an extra WAD of precision to maintain precision in the math when applied over long durations
    uint256 private _rentalFeesOwedPerEpoch = FixedPointMathLib.divWadUp(15e34, EPOCHS_IN_YEAR * 1e18);

    /// @dev _lpRewards tracks the accrual math for LP rewards
    RewardAccrual private _lpRewards;

    /// @dev _treasuryRewards tracks the accrual math for treasury rewards
    RewardAccrual private _treasuryRewards;

    /// @dev _rateUpdate tracks the rate updates for the pool, which may take more than 1 transaction depending on how many accounts are there
    RateUpdate private _rateUpdate;

    /// @dev _maxAccountsToUpdatePerBatch is the maximum number of accounts that can be updated in a single transaction
    uint256 private _maxAccountsToUpdatePerBatch = 250;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERs
    //////////////////////////////////////////////////////////////*/

    /// @dev a modifier that ensures the caller matches the `vc.subject` and that the caller is an agent
    modifier subjectIsAgentCaller(VerifiableCredential calldata vc) {
        _subjectIsAgentCaller(vc);
        _;
    }

    modifier ownerIsCaller(address owner) {
        if (msg.sender != owner.normalize()) revert Unauthorized();
        _;
    }

    modifier isOpen() {
        _isOpen();
        _;
    }

    modifier isValidReceiver(address receiver) {
        if (receiver == address(0) || receiver == address(this)) revert InvalidReceiver();
        _;
    }

    /*////////////////////////////////////////////////////////
                      Payable Fallbacks
    ////////////////////////////////////////////////////////*/

    /// @dev the pool can receive FIL from the WFIL.Withdraw method,
    /// so we make sure to not trigger a deposit in those cases
    /// (when this contract unwraps FIL triggering a receive or fallback)
    receive() external payable isOpen whenNotPaused {
        if (msg.sender != address(asset)) _depositFIL(msg.sender);
    }

    fallback() external payable isOpen whenNotPaused {
        if (msg.sender != address(asset)) _depositFIL(msg.sender);
    }

    constructor(
        address owner_,
        address router_,
        address liquidStakingToken_,
        address lm_,
        uint256 minimumLiquidity_,
        uint256 id_
    ) Ownable(owner_) {
        _router = router_;
        asset = IERC20(IRouter(_router).getRoute(ROUTE_WFIL_TOKEN));
        minimumLiquidity = minimumLiquidity_;
        // set the ID
        id = id_;
        // deploy a new liquid staking token for the pool
        liquidStakingToken = IPoolToken(liquidStakingToken_);

        _agentFactory = GetRoute.agentFactory(router_);
        credParser = address(GetRoute.credParser(router_));
        lm = ILiquidityMineSP(lm_);

        // start the contract pause
        _pause();
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the amount a specific Agent has borrowed from this pool
     * @param agentID The ID of the agent
     * @return totalBorrowed The total borrowed from the agent
     */
    function getAgentBorrowed(uint256 agentID) external view returns (uint256) {
        return AccountHelpers.getAccount(_router, agentID, id).principal;
    }

    /**
     * @dev Returns the amount a specific Agent owes to the pool (includes principal and interest)
     * @param agentID The ID of the agent
     * @return totalDebt The total borrowed + interest owed
     */
    function getAgentDebt(uint256 agentID) external view returns (uint256) {
        return FinMath.computeDebt(AccountHelpers.getAccount(_router, agentID, id), _rentalFeesOwedPerEpoch);
    }

    /**
     * @dev Returns the amount a specific Agent owes to the pool (includes only interest)
     * @param agentID The ID of the agent
     * @return totalDebt The total interest owed
     */
    function getAgentInterestOwed(uint256 agentID) external view returns (uint256) {
        (uint256 _interestOwed,) =
            FinMath.interestOwed(AccountHelpers.getAccount(_router, agentID, id), _rentalFeesOwedPerEpoch);
        return _interestOwed;
    }

    function lpRewards() external view returns (RewardAccrual memory) {
        (uint256 newRentalFees,) = _computeNewFeesAccrued();
        return _lpRewards.accrue(newRentalFees);
    }

    function treasuryRewards() external view returns (RewardAccrual memory) {
        (, uint256 newTreasuryFeesOwed) = _computeNewFeesAccrued();
        return _treasuryRewards.accrue(newTreasuryFeesOwed);
    }

    function rateUpdate() external view returns (RateUpdate memory) {
        return _rateUpdate;
    }

    /**
     * @dev Returns the amount of liquid FIL in this pool that is reserved for the treasury due to fees
     * @return treasuryFeesReserved The total treasury rewards that have accrued in this pool
     */
    function treasuryFeesOwed() public view returns (uint256) {
        (, uint256 newTreasuryFeesOwed) = _computeNewFeesAccrued();
        return _treasuryRewards.accrue(newTreasuryFeesOwed).owed();
    }

    /**
     * @dev Returns the totalAssets of the pool
     * @return totalAssets The total assets of the pool
     */
    function totalAssets() public view override returns (uint256) {
        // pseudo accounting update to make sure our values are correct
        (uint256 newRentalFeesAccrued, uint256 newTFeesAccrued) = _computeNewFeesAccrued();
        // using accrual basis accounting, the assets of the pool are:
        // assets currently held by the pool
        // total borrowed from agents
        // total owed rental fees to LPs
        // subtract owed treasury fees
        return asset.balanceOf(address(this)) + totalBorrowed + _lpRewards.accrue(newRentalFeesAccrued).owed()
            - _treasuryRewards.accrue(newTFeesAccrued).owed();
    }

    /**
     * @dev Returns the amount of assets in the Pool that Agents can borrow
     * @return totalBorrowed The total borrowed from the agent
     */
    function totalBorrowableAssets() public view returns (uint256) {
        if (isShuttingDown || paused()) return 0;
        uint256 _assets = asset.balanceOf(address(this));
        uint256 _absMinLiquidity = getAbsMinLiquidity();

        if (_assets < _absMinLiquidity) return 0;
        return _assets - _absMinLiquidity;
    }

    /**
     * @dev Returns the amount of FIL the Pool aims to keep in reserves at the current epoch
     * @return minLiquidity The minimum amount of FIL to keep in reserves
     * @dev the minimumLiquidity percentage is multiplied by the totalAssets, less accrued interest and accrued treasury fees, to arrive at the basis in which the minLiquidity % should be applied
     */
    function getAbsMinLiquidity() public view returns (uint256) {
        return (asset.balanceOf(address(this)) + totalBorrowed).mulWadUp(minimumLiquidity);
    }

    /**
     * @dev Returns the amount of liquid WFIL held by the Pool, used for determining max withdraw/redeem amounts
     * @return liquidFunds The amount of total liquid assets held in the Pool
     */
    function getLiquidAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /**
     * @notice getRate returns the rate for an Agent's current position within the Pool
     * @return rate The rate for the Agent's current position and base rate
     */
    function getRate() public view returns (uint256 rate) {
        return _rentalFeesOwedPerEpoch;
    }

    /**
     * @notice writeOff writes down the Agent's account and the Pool's borrowed amount after a liquidation
     * @param agentID The ID of the Agent
     * @param recoveredFunds The amount of funds recovered from the liquidation. This is the total amount the Police was able to recover from the Agent's Miner Actors
     * @dev the capital stack works as follows on a write off:
     *  1. pay off interest
     *  2. pay off principal
     *  3. with any excess, treasury takes a 10% fee on the total liquidated value
     *  4. With any excess after liquidation fee, the agent's owner gets the remainder
     */
    function writeOff(uint256 agentID, uint256 recoveredFunds) external {
        // only the agent police can call this function
        _onlyAgentPolice();

        updateAccounting();

        Account memory account = _getAccount(agentID);

        if (account.defaulted) revert AlreadyDefaulted();
        // set the account to defaulted
        account.defaulted = true;

        uint256 interestOwed = 0;
        uint256 _treasuryFeesOwed = 0;
        // if the account is not "current", compute the amount of interest owed based on the penalty rate
        if (account.epochsPaid < block.number) {
            (interestOwed,) = FinMath.interestOwed(account, _rentalFeesOwedPerEpoch);
            _treasuryFeesOwed = interestOwed.mulWadDown(treasuryFeeRate);
        }

        // compute the amount of fees and principal we can pay off
        uint256 totalOwed = interestOwed + account.principal;
        // the amount of fees that will be paid
        uint256 feeBasis = 0;
        // the amount of principal that will be paid
        uint256 principalPaid = 0;
        // the amount of rental fees lost in this write-off
        uint256 lostFees = 0;
        // the amount of principal lost in this write-off
        uint256 lostPrincipal = 0;
        if (recoveredFunds <= interestOwed) {
            // if we can't cover the whole interest payment, we cover what we can
            feeBasis = recoveredFunds;
            // we lost interest
            lostFees = interestOwed - recoveredFunds;
            // we lost full principal
            lostPrincipal = account.principal;
            // pull in only the assets we need - in this case, the full recovery amount
            asset.transferFrom(msg.sender, address(this), recoveredFunds);
        } else if (recoveredFunds <= totalOwed - _treasuryFeesOwed) {
            // in this case we do not have enough recovered funds to make everyone whole
            // no interest lost
            feeBasis = interestOwed;
            // cover any principal with the remainder
            principalPaid = recoveredFunds - interestOwed;
            // we lost some principal
            lostPrincipal = account.principal - principalPaid;
            // pull in only the assets we need - in this case, the full recovery amount
            asset.transferFrom(msg.sender, address(this), recoveredFunds);
        } else {
            // we can cover everything
            feeBasis = interestOwed;
            principalPaid = account.principal;
            // in this case, we want to avoid pulling in excess fees that would go to the treasury to avoid adding treasury fees to LP rewards through the balanceOf check in totalAssets
            asset.transferFrom(msg.sender, address(this), feeBasis.mulWadUp(1e18 - treasuryFeeRate) + principalPaid);
        }

        // write off the pool's account so that the pool's total borrowed is accurate
        totalBorrowed -= account.principal;
        // since this account's principal still accrues debt up to this point in time, we need to update the paid fees one last time, and mark the lost amount
        _lpRewards = _lpRewards.payout(feeBasis).writeoff(lostFees);
        // update lost treasury fees
        _treasuryRewards = _treasuryRewards.writeoff(interestOwed.mulWadDown(treasuryFeeRate));
        // set the account with the funds the pool lost, this isn't used anywhere else in the protocol, just for querying later
        account.principal = lostFees + lostPrincipal;

        account.save(_router, agentID, id);

        if (address(lm) != address(0)) {
            // lm will burn this agent's rewards on a default
            lm.onDefault(agentID);
        }

        emit WriteOff(agentID, recoveredFunds, lostFees + lostPrincipal, feeBasis);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL BORROWING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice borrow borrows funds from the Pool. Will revert if the Agent is not approved to borrow
     * @param vc The Agent's VerifiableCredential - the `subject` must be the Agent's ID and the `value` must be the amount to borrow
     * @dev the Agent must be approved to borrow from the Pool
     * @dev the min borrow amount is 1 FIL
     */
    function borrow(VerifiableCredential calldata vc) external isOpen whenNotPaused subjectIsAgentCaller(vc) {
        updateAccounting();
        // 1e18 => 1 FIL, can't borrow less than 1 FIL
        if (vc.value < WAD) revert InvalidParams();
        // can't borrow more than the pool has
        if (totalBorrowableAssets() < vc.value) revert InsufficientLiquidity();
        Account memory account = _getAccount(vc.subject);

        // fresh account, set start epoch and epochsPaid to beginning of current window
        if (account.epochsPaid == 0) {
            uint256 currentEpoch = block.number;
            account.startEpoch = currentEpoch;
            account.epochsPaid = currentEpoch;
            account.principal += vc.value;
        } else {
            // if the account already exists, we need to shift the epochsPaid cursor up,
            // so the account does not end up overpaying interest on previously borrowed funds
            // first we compute the interest owed before the new borrowed amount is applied
            (uint256 interestOwed,) = FinMath.interestOwed(account, _rentalFeesOwedPerEpoch);
            // then add the new borrowed amount to the account's principal
            account.principal += vc.value;
            // recompute the new epochs paid cursor
            (uint256 newEpochsPaid, uint256 newInterestIncurred) =
                _resetEpochsPaid(account, _rentalFeesOwedPerEpoch, interestOwed);
            // update the account's `epochsPaid` cursor
            account.epochsPaid = newEpochsPaid;

            if (newInterestIncurred > 0) {
                // accrue any new rewards to the pool (due to dust rounding)
                _lpRewards = _lpRewards.accrue(newInterestIncurred);
            }
            // if we dont owe any interest we leave the account epoch's paid cursor alone
        }

        account.save(_router, vc.subject, id);

        totalBorrowed += vc.value;

        emit Borrow(vc.subject, vc.value);

        // interact - here `msg.sender` must be the Agent bc of the `subjectIsAgentCaller` modifier
        asset.transfer(msg.sender, vc.value);
    }

    /**
     * @notice pay handles the accounting for a payment from the Agent to the Infintiy Pool
     * @param vc The Agent's VerifiableCredential - the `subject` must be the Agent's ID and the `value` must be the amount to pay
     * @dev The pay function applies the payment amount to the interest owed on the account first. If the entire interest owed is paid off by the payment, then the remainder is applied to the principal owed on the account.
     * @dev Treasury fees only apply to interest payments, not principal payments
     */
    function pay(VerifiableCredential calldata vc)
        external
        subjectIsAgentCaller(vc)
        whenNotPaused
        returns (uint256 rate, uint256 epochsPaid, uint256 principalPaid, uint256 refund)
    {
        updateAccounting();
        // grab this Agent's account from storage
        Account memory account = _getAccount(vc.subject);
        // ensure we're not making payments to a non-existent account
        if (!account.exists()) revert AccountDNE();
        // the total interest amount owed to get the epochsPaid cursor to the current epoch
        uint256 interestOwed;
        // rate * principal, used for computing the interest owed and moving the epochsPaid cursor
        uint256 interestPerEpoch;
        // the amount of interest paid on this payment, used for computing the treasury fee
        uint256 feeBasis;

        // if the account is "defaulted", we treat everything as interest
        // here we would have already forfeited the agent's LM reward tokens, so we dont interact with the LM contract in this case
        if (account.defaulted) {
            // here we explicitly do not update the paidRentalFees, the balanceOf check ecompasses the increase in assetss
            // transfer the assets into the pool
            asset.transferFrom(msg.sender, address(this), vc.value);

            emit Pay(vc.subject, vc.value, vc.value, 0, 0);

            return (_rentalFeesOwedPerEpoch, account.epochsPaid, 0, 0);
        }

        // if the account is not "current", compute the amount of interest owed based on the new rate
        if (account.epochsPaid < block.number) {
            (interestOwed, interestPerEpoch) = FinMath.interestOwed(account, _rentalFeesOwedPerEpoch);
            // ensure the payment is greater than or equal to at least 1 epochs worth of interest
            // NOTE - we multiply by WAD here because the interestPerEpoch has an extra WAD to maintain precision
            if (vc.value * WAD < interestPerEpoch) revert InvalidParams();
        }
        // if the payment is less than the interest owed, pay interest only
        if (vc.value < interestOwed) {
            // compute the amount of epochs this payment covers
            // vc.value is not WAD yet, so divWadDown cancels the extra WAD in interestPerEpoch
            uint256 epochsForward = vc.value.divWadDown(interestPerEpoch);

            // here we recalculate how much interest should be paid based on the epochsForward, so we don't overcharge the user for interest that does not bring the account over the next epochsPaid cursor
            uint256 recomputedInterestOwed = epochsForward.mulWadUp(interestPerEpoch);

            feeBasis = vc.value;
            // if the recomputed interest owed is less than the payment, adjust the payment to be the recomputed interest owed
            if (recomputedInterestOwed < vc.value) {
                feeBasis = recomputedInterestOwed;
                // mark the excess as a refund to the agent
                refund = vc.value - recomputedInterestOwed;
            }
            // update the account's `epochsPaid` cursor
            account.epochsPaid += epochsForward;
            // since the entire payment is interest, the entire payment is used to compute the fee (principal payments are fee-free)
        } else {
            // the portion of the payment that will go towards principal
            uint256 principalPayment = vc.value - interestOwed;
            // the fee basis only applies to the interest payment
            feeBasis = interestOwed;
            // fully paid off
            if (principalPayment >= account.principal) {
                // the amount paid is account.principal
                principalPaid = account.principal;
                // write down totalBorrowed by the account.principal
                totalBorrowed -= principalPaid;
                // return the amount of funds overpaid
                refund = principalPayment - account.principal;
                // reset the account
                account.reset();
            } else {
                // partial principal payment, the principalPayment is the amount paid
                principalPaid = principalPayment;
                // write down totalBorrowed by the principalPayment
                totalBorrowed -= principalPayment;
                // interest and partial principal payment
                account.principal -= principalPayment;
                // move the `epochsPaid` cursor to mark the account as "current"
                account.epochsPaid = block.number;
            }
        }
        // update the account in storage
        account.save(_router, vc.subject, id);
        // realize fees paid to the pool
        _lpRewards = _lpRewards.payout(feeBasis);
        // transfer the assets into the pool
        asset.transferFrom(msg.sender, address(this), feeBasis + principalPaid);
        // call out to the LM hook to accrue rewards for this agent
        if (address(lm) != address(0)) lm.onPaymentMade(vc.subject, feeBasis);

        emit Pay(vc.subject, vc.value, feeBasis, principalPaid, _rentalFeesOwedPerEpoch);

        return (_rentalFeesOwedPerEpoch, account.epochsPaid, principalPaid, refund);
    }

    /**
     * @dev Updates the accrual basis accounting of the pool
     */
    function updateAccounting() public {
        // only update the accounting if we're in a new epoch
        if (block.number > lastAccountingUpdateEpoch && !paused()) {
            (uint256 newRentalFeesAccrued, uint256 newTreasuryFeesOwed) = _computeNewFeesAccrued();
            // accrue rewards to the treasury fees owed
            _treasuryRewards = _treasuryRewards.accrue(newTreasuryFeesOwed);
            _lpRewards = _lpRewards.accrue(newRentalFeesAccrued);
            uint256 previousAccountingUpdatingEpoch = lastAccountingUpdateEpoch;
            lastAccountingUpdateEpoch = block.number;

            emit UpdateAccounting(
                msg.sender,
                newRentalFeesAccrued,
                _lpRewards.accrued,
                previousAccountingUpdatingEpoch,
                lastAccountingUpdateEpoch,
                convertToAssets(WAD)
            );
        }
    }

    function _computeNewFeesAccrued()
        internal
        view
        returns (uint256 newRentalFeesAccrued, uint256 newTreasuryFeesAccrued)
    {
        // only update the accounting if we're in a new epoch and not paused
        if (block.number > lastAccountingUpdateEpoch && !paused()) {
            // create a pseudo Account struct for the whole pool to reuse the FinMath library
            (newRentalFeesAccrued,) = FinMath.interestOwed(
                Account({
                    principal: totalBorrowed,
                    startEpoch: lastAccountingUpdateEpoch,
                    epochsPaid: lastAccountingUpdateEpoch,
                    defaulted: false
                }),
                _rentalFeesOwedPerEpoch
            );

            newTreasuryFeesAccrued = newRentalFeesAccrued.mulWadDown(treasuryFeeRate);
            // div out the extra wad embedded in the rate for increase precision
            return (newRentalFeesAccrued, newTreasuryFeesAccrued);
        }
        return (0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            4626 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows Staker to deposit assets and receive shares in return
     * @param assets The amount of assets to deposit
     * @param receiver The address that will receive the shares
     * @return shares - the number of shares received in exchange for the deposit
     */
    function deposit(uint256 assets, address receiver)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        returns (uint256 shares)
    {
        return _deposit(assets, receiver);
    }

    /**
     * @dev Allows Staker to deposit native FIL and receive shares in return
     * @param receiver The address that will receive the shares
     * @return shares - the number of shares received in exchange for the deposit
     */
    function deposit(address receiver)
        public
        payable
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        returns (uint256 shares)
    {
        return _depositFIL(receiver);
    }

    /**
     * @dev Allows Staker to specify the number of `shares` to mint from the Pool by depositing `assets`
     * @param shares Number of shares to mint
     * @param receiver The address to receive the shares
     * @return assets Number of assets deposited
     */
    function mint(uint256 shares, address receiver)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        returns (uint256 assets)
    {
        updateAccounting();
        // These transfers need to happen before the mint, and this is forcing a higher degree of coupling than is ideal
        assets = previewMint(shares);
        if (assets == 0 || shares == 0) revert InvalidParams();
        asset.transferFrom(msg.sender, address(this), assets);
        liquidStakingToken.mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Allows the Staker to redeem their shares for assets
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 assets)
    {
        return _redeem(shares, receiver, owner);
    }

    /**
     * @notice Allows the Staker to redeem their shares for assets
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     *  @param (unused) A patch to match the old Offramp interface
     * @return assets The assets received from burning the shares
     */
    function redeem(uint256 shares, address receiver, address owner, uint256)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 assets)
    {
        return _redeem(shares, receiver, owner);
    }

    /**
     * @notice Allows the Staker to redeem their shares for assets (FIL)
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeemF(uint256 shares, address receiver, address owner)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 assets)
    {
        updateAccounting();
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, true);
    }

    /**
     * @notice DEPRECATED: Allows the Staker to redeem their shares for assets (FIL)
     * @dev This param is a patch for the Offramp to maintain backwards compatibility
     */
    function redeemF(uint256 shares, address receiver, address owner, uint256)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 assets)
    {
        updateAccounting();
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, true);
    }

    /// @dev _redeem is an internal method that handles the redeem logic
    function _redeem(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        updateAccounting();
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, false);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Allows Staker to withdraw assets
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 shares)
    {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, false);
    }

    /**
     * @notice Allows Staker to withdraw assets
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     *  @param (unused) A patch to match the old Offramp interface
     * @return shares - the number of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner, uint256)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 shares)
    {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, false);
    }

    /**
     * @notice Allows Staker to withdraw assets (FIL)
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdrawF(uint256 assets, address receiver, address owner)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 shares)
    {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, true);
    }

    /**
     * @notice DEPRECATED: Allows Staker to withdraw assets (FIL)
     * @dev This param is a patch for the Offramp to maintain backwards compatibility
     */
    function withdrawF(uint256 assets, address receiver, address owner, uint256)
        public
        isOpen
        whenNotPaused
        isValidReceiver(receiver)
        ownerIsCaller(owner)
        returns (uint256 shares)
    {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, true);
    }

    /// @dev _withdraw is an internal method that handles the withdrawal logic
    function _withdraw(uint256 assets, address receiver, address owner) internal returns (uint256 shares) {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, false);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            4626 LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Converts `assets` to shares
     * @param assets The amount of assets to convert
     * @return shares - The amount of shares converted from assets
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    /**
     * @dev Converts `shares` to assets
     * @param shares The amount of shares to convert
     * @return assets - The amount of assets converted from shares
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    /**
     * @notice Previews an amount of shares that would be received for depositing `assets`
     * @param assets The amount of assets to preview deposit
     * @return shares - The amount of shares that would be converted from assets
     * @dev Will revert if the pool is shutting down
     */
    function previewDeposit(uint256 assets) public view isOpen whenNotPaused returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice Previews an amount of assets that would be needed to mint `shares`
     * @param shares The amount of shares to mint
     * @return assets - The amount of assets that would be converted from shares
     * @dev Will revert if the pool is shutting down
     */
    function previewMint(uint256 shares) public view isOpen whenNotPaused returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @notice Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets) public view isOpen whenNotPaused returns (uint256 shares) {
        if (assets > getLiquidAssets()) return 0;

        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        shares = supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    /**
     * @notice Previews an amount of assets to redeem for a given number of `shares`
     * @param shares The amount of shares to hypothetically burn
     * @return assets - The amount of assets that would be converted from shares
     */
    function previewRedeem(uint256 shares) public view isOpen whenNotPaused returns (uint256 assets) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        assets = supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
        // revert if the fil value of the account's shares is bigger than the available exit liquidity
        if (assets > getLiquidAssets()) return 0;
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) external view returns (uint256) {
        return Math.min(convertToAssets(liquidStakingToken.balanceOf(owner)), getLiquidAssets());
    }

    function maxRedeem(address owner) external view returns (uint256 shares) {
        shares = liquidStakingToken.balanceOf(owner);
        uint256 filValOfShares = convertToAssets(shares);

        // if the fil value of the owner's shares is bigger than the available exit liquidity
        // return the share equivalent of the pool's total liquid assets
        uint256 liquidAssets = getLiquidAssets();
        if (filValOfShares > liquidAssets) {
            return previewRedeem(liquidAssets);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Distributes treasuryFeesOwed to the treasury
     */
    function harvestFees(uint256 harvestAmount) public {
        updateAccounting();
        // if we dont have enough to pay out the harvest amount, revert
        if (harvestAmount > asset.balanceOf(address(this)) || harvestAmount > treasuryFeesOwed()) {
            revert InsufficientLiquidity();
        }
        _treasuryRewards = _treasuryRewards.payout(harvestAmount);
        asset.transfer(GetRoute.treasury(_router), harvestAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice decomissionPool shuts down the pool and transfers all assets to the new pool
     * @param newPool The address of new pool to transfer assets to
     */
    function decommissionPool(address newPool) external onlyOwner returns (uint256 borrowedAmount) {
        if (IPool(newPool).id() != id || !isShuttingDown) revert InvalidState();
        // forward fees to the treasury
        harvestFees(treasuryFeesOwed());

        asset.transfer(address(newPool), asset.balanceOf(address(this)));

        borrowedAmount = totalBorrowed;
    }

    /**
     * @notice recoverFIL recovers any FIL that was accidentally sent to this contract
     * @dev this can only occur on FEVM through a raw send to this actor
     */
    function recoverFIL(address receiver) external onlyOwner {
        if (address(this).balance > 0) {
            payable(receiver).sendValue(address(this).balance);
        }
    }

    /**
     * @notice recoverERC20 recovers any ERC20 that was accidentally sent to this contract
     */
    function recoverERC20(address receiver, IERC20 token) external onlyOwner {
        // cannot unstuck the Pool's native asset (wFIL)
        if (token == asset) revert Unauthorized();

        token.transfer(receiver.normalize(), token.balanceOf(address(this)));
    }

    /**
     * @notice jumpStartTotalBorrowed sets the totalBorrowed variable to the given amount in the pool
     * @dev this is only called in a pool upgrade scenario
     */
    function jumpStartTotalBorrowed(uint256 amount) external {
        updateAccounting();
        // this function gets called from the v0 pool registry in the initial upgrade to v2
        if (address(GetRoute.poolRegistry(_router)) != msg.sender) revert Unauthorized();
        if (totalBorrowed != 0) revert InvalidState();
        // set the lastAccountingUpdateEpoch, effectively starting the pool's accounting
        lastAccountingUpdateEpoch = block.number;
        totalBorrowed = amount;
        // set the pool to unpause to start operations
        _unpause();
    }

    /**
     * @notice jumpStartAccount allows the pool's owner to create an account for an agent that was made outside the pool
     * @param receiver The address to credit with the borrow amount in iFIL
     * @param agentID The ID of the agent to create an account for
     * @param accountPrincipal The principal amount to create the account with
     */
    function jumpStartAccount(address receiver, uint256 agentID, uint256 accountPrincipal) external onlyOwner {
        updateAccounting();

        Account memory account = _getAccount(agentID);
        // if the account is already initialized, revert
        if (account.principal != 0) revert InvalidState();
        // create the account
        account.principal = accountPrincipal;
        account.startEpoch = block.number;
        account.epochsPaid = block.number;
        // save the account
        account.save(_router, agentID, id);
        // mint the iFIL to the receiver, using principal as the deposit amount
        liquidStakingToken.mint(receiver, convertToShares(accountPrincipal));
        // account for the new principal in the total borrowed of the pool
        totalBorrowed += accountPrincipal;
    }

    /**
     * @notice setMinimumLiquidity sets the liquidity reserve threshold used for exits
     */
    function setMinimumLiquidity(uint256 _minimumLiquidity) external onlyOwner {
        updateAccounting();
        minimumLiquidity = _minimumLiquidity;
    }

    /**
     * @notice setTreasuryFeeRate sets the treasury fee rate
     */
    function setTreasuryFeeRate(uint256 _treasuryFeeRate) external onlyOwner {
        updateAccounting();
        treasuryFeeRate = _treasuryFeeRate;
    }

    /**
     * @notice shutDown sets the isShuttingDown variable to true, effectively halting all deposits and borrows
     */
    function shutDown() external onlyOwner {
        updateAccounting();
        isShuttingDown = true;
    }

    /**
     * @notice startRateUpdate sets the rental fees owed per epoch after adjusting accounts
     * @param rentalFeesOwedPerEpoch_ The new rental fees owed per epoch
     */
    function startRateUpdate(uint256 rentalFeesOwedPerEpoch_) external onlyOwner {
        updateAccounting();

        if (_rateUpdate.inProcess) revert InvalidState();

        // pause the contract to ensure that nothing happens after we start updating accounts
        _pause();

        // loop through each account and update the epochsPaid cursor to maintain the same amount of interest owed at the new rate
        uint256 totalAgents = _agentFactory.agentCount();
        // agents are 1 indexed, so we start at 1, until we reach the limit or the total number of agents
        uint256 aggNewInterestIncurred =
            _updateAgentAccounts(rentalFeesOwedPerEpoch_, 1, Math.min(_maxAccountsToUpdatePerBatch, totalAgents));
        if (aggNewInterestIncurred > 0) {
            // accrue any new rewards to the pool (due to dust)
            _lpRewards = _lpRewards.accrue(aggNewInterestIncurred);
        }

        // if we can update all accounts in one go, we unpause the pool and set the new rate to complete the rate update
        if (_maxAccountsToUpdatePerBatch >= totalAgents) {
            _unpause();
            _rentalFeesOwedPerEpoch = rentalFeesOwedPerEpoch_;
        } else {
            // if we didnt update all accounts, don't update the rate in storage until the process is complete
            _rateUpdate = RateUpdate({
                totalAccountsAtUpdate: totalAgents,
                totalAccountsClosed: _maxAccountsToUpdatePerBatch,
                newRate: rentalFeesOwedPerEpoch_,
                inProcess: true
            });
        }
    }

    /**
     * @notice continueRateUpdate continues the rate update process
     */
    function continueRateUpdate() external onlyOwner {
        if (!_rateUpdate.inProcess) revert InvalidState();

        uint256 totalClosed = _rateUpdate.totalAccountsClosed;
        uint256 totalAgents = _rateUpdate.totalAccountsAtUpdate;
        uint256 maxAgentsToUpdate = _maxAccountsToUpdatePerBatch + totalClosed;

        uint256 stopIdx = Math.min(maxAgentsToUpdate, totalAgents);

        uint256 aggNewInterestIncurred = _updateAgentAccounts(_rateUpdate.newRate, totalClosed + 1, stopIdx);
        if (aggNewInterestIncurred > 0) {
            // accrue any new rewards to the pool (due to dust)
            _lpRewards = _lpRewards.accrue(aggNewInterestIncurred);
        }

        // if we finish updating all accounts, we unpause the pool, set the new rate, and
        // update accounting for the epochs when the pool was paused (paused epochs are applied at the new rate)
        if (stopIdx == totalAgents) {
            _unpause();
            _rentalFeesOwedPerEpoch = _rateUpdate.newRate;
            updateAccounting();
            // end the rate update
            _rateUpdate = RateUpdate({totalAccountsAtUpdate: 0, totalAccountsClosed: 0, newRate: 0, inProcess: false});
        } else {
            // otherwise we continue with the rate update
            _rateUpdate = RateUpdate({
                totalAccountsAtUpdate: totalAgents,
                totalAccountsClosed: maxAgentsToUpdate,
                newRate: _rateUpdate.newRate,
                inProcess: true
            });
        }
    }

    function _updateAgentAccounts(uint256 rate, uint256 startIdx, uint256 stopIdx)
        internal
        returns (uint256 aggNewInterestIncurred)
    {
        Account memory account;
        uint256 interestOwed;
        uint256 newEpochsPaid;
        uint256 newInterestIncurred;
        for (uint256 i = startIdx; i <= stopIdx; i++) {
            account = _getAccount(i);
            // if  account principal is 0, then the account does not need an update
            if (account.principal == 0) continue;
            // get the existing interest owed on the account
            (interestOwed,) = FinMath.interestOwed(account, _rentalFeesOwedPerEpoch);
            // shift the epochs paid cursor forward or backwards depending on the new rate
            (newEpochsPaid, newInterestIncurred) = _resetEpochsPaid(account, rate, interestOwed);
            // if we incurred any new debt in the books closing, make sure to account for it in in the LP rewards
            aggNewInterestIncurred += newInterestIncurred;
            // update the account's `epochsPaid` cursor
            account.epochsPaid = newEpochsPaid;
            // save the account in storage
            account.save(_router, i, id);
        }

        return aggNewInterestIncurred;
    }

    function setMaxAccountsToUpdatePerBatch(uint256 maxAccountsToUpdatePerBatch_) external onlyOwner {
        updateAccounting();

        _maxAccountsToUpdatePerBatch = maxAccountsToUpdatePerBatch_;
    }

    /**
     * @notice pause halts all pool activity
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice unpause resumes all pool activity
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @dev sets the credentialParser in case we need to update a data type
    function updateCredParser() external onlyOwner {
        credParser = address(GetRoute.credParser(_router));
    }

    /**
     * @notice refreshRoutes refreshes the pool's cached routes
     */
    function refreshRoutes() external {
        _agentFactory = GetRoute.agentFactory(_router);
        credParser = address(GetRoute.credParser(_router));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccount(uint256 agent) internal view returns (Account memory) {
        return AccountHelpers.getAccount(_router, agent, id);
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 lstAmount) {
        updateAccounting();
        // get the number of iFIL tokens to mint
        lstAmount = previewDeposit(assets);
        // Check for rounding error since we round down in previewDeposit.
        if (assets == 0 || lstAmount == 0) revert InvalidParams();
        // pull in the assets
        asset.transferFrom(msg.sender, address(this), assets);
        // mint the iFIL tokens
        liquidStakingToken.mint(receiver, lstAmount);

        emit Deposit(msg.sender, receiver.normalize(), assets, lstAmount);
    }

    function _depositFIL(address receiver) internal returns (uint256 lstAmount) {
        updateAccounting();

        if (msg.value == 0) revert InvalidParams();

        lstAmount = previewDeposit(msg.value);

        // handle FIL deposit
        IWFIL(address(asset)).deposit{value: msg.value}();

        liquidStakingToken.mint(receiver, lstAmount);

        emit Deposit(msg.sender, receiver.normalize(), msg.value, lstAmount);
    }

    function _resetEpochsPaid(Account memory account, uint256 perEpochRate, uint256 interestOwed)
        internal
        view
        returns (uint256 newAccountEpochsPaid, uint256 newInterestIncurred)
    {
        uint256 interestPerEpoch = FinMath.interestPerEpoch(account, perEpochRate);
        if (interestOwed > 0 && (interestOwed <= interestPerEpoch.mulWadUp(1))) {
            // add the difference between the new interest owed (after divving out the extra WAD) and previousInterestOwed to the accruedFees of the pool
            return (block.number - 1, interestPerEpoch.mulWadUp(1) - interestOwed);
        } else if (interestOwed > 0) {
            // if the interestOwed is bigger than 0 and the interestPerEpoch, adjust the epochsPaid cursor forward
            // given a new interest per epoch owed with the new borrow amount applied, solve for
            // the number of epochs (at the new interestPerEpochRate) that will result in the same amount of interest owed
            newAccountEpochsPaid = block.number - interestOwed.divWadUp(interestPerEpoch);
            account.epochsPaid = newAccountEpochsPaid;
            (uint256 newInterestOwed,) = FinMath.interestOwed(account, perEpochRate);
            // since we lost precision by dividing into epochs (not wad based), check for any accounting mismatches
            if (newInterestOwed != interestOwed) {
                // add the difference between the new interest owed and previousInterestOwed to the accruedFees of the pool
                return (newAccountEpochsPaid, newInterestOwed - interestOwed);
            }
            return (newAccountEpochsPaid, 0);
        }

        return (account.epochsPaid, 0);
    }

    function _processExit(
        address owner,
        address receiver,
        uint256 iFILToBurn,
        uint256 assetsToReceive,
        bool shouldConvert
    ) internal {
        // normalize to protect against sending to ID address of EVM actor
        receiver = receiver.normalize();
        owner = owner.normalize();
        // if the pool can't process the entire exit, it reverts
        if (assetsToReceive > getLiquidAssets()) revert InsufficientLiquidity();
        // pull in the iFIL from the iFIL holder, which will decrease the allowance of this ramp to spend on behalf of the iFIL holder
        liquidStakingToken.transferFrom(owner, address(this), iFILToBurn);
        // burn the exiter's iFIL tokens
        liquidStakingToken.burn(address(this), iFILToBurn);

        // here we unwrap the amount of WFIL and transfer native FIL to the receiver
        if (shouldConvert) {
            // unwrap the WFIL into FIL
            IWFIL(address(asset)).withdraw(assetsToReceive);
            // send FIL to the receiver, normalize to protect against sending to ID address of EVM actor
            payable(receiver).sendValue(assetsToReceive);
        } else {
            // send WFIL back to the receiver
            asset.transfer(receiver, assetsToReceive);
        }

        emit Withdraw(owner, receiver, owner, assetsToReceive, iFILToBurn);
    }

    function _subjectIsAgentCaller(VerifiableCredential calldata vc) internal view {
        if (vc.subject == 0 || _agentFactory.agents(msg.sender) != vc.subject) revert Unauthorized();
    }

    function _isOpen() internal view {
        if (isShuttingDown) revert PoolShuttingDown();
    }

    function _onlyAgentPolice() internal view {
        if (address(GetRoute.agentPolice(_router)) != msg.sender) revert Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                        POOL REGISTRY FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @dev these functions patch the pool registry interface in areas that are hard to upgrade (specifically calls to setAccount in the router)

    /// @dev allPoolsLength is hardcoded to 1 as there will now only ever be 1 pool (this one)
    function allPoolsLength() external pure returns (uint256) {
        return 1;
    }

    /// @dev allPools is hardcoded to return the pool itself
    function allPools(uint256) external view returns (address) {
        return address(this);
    }

    ////////////
    //@audit => new
    ////////////

    function getLpRewardsValues() external view returns (uint256, uint256, uint256) {
        return (_lpRewards.accrued, _lpRewards.paid, _lpRewards.lost);
    }

    function getTreasuryRewardsValues() external view returns (uint256, uint256, uint256) {
        return (_treasuryRewards.accrued, _treasuryRewards.paid, _treasuryRewards.lost);
    }

    function paused() public view override(IPool, Pausable) returns (bool) {
        return super.paused();
    }

    function getAccount(uint256 agent) external view returns (Account memory) {
        return AccountHelpers.getAccount(_router, agent, id);
    }
}
