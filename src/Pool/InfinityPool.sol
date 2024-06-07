    // SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";

import {GetRoute} from "src/Router/GetRoute.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {AccountHelpers} from "src/Pool/Account.sol";

import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPreStake} from "src/Types/Interfaces/IPreStake.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

/**
 * @title InfinityPool
 * @author GLIF
 * @notice The InfinityPool contract is an ERC4626 vault for FIL. It primarily handles depositing, borrowing, and paying FIL.
 * @dev the InfinityPool has some hooks and light integrations with the Offramp. The Offramp will not be enabled during launch.
 */
contract InfinityPool is IPool, Ownable {
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FilAddress for address;
    using FilAddress for address payable;
    using FixedPointMathLib for uint256;

    error InsufficientLiquidity();
    error AccountDNE();
    error InvalidState();
    error PoolShuttingDown();
    error AlreadyDefaulted();
    error PayUp();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 constant WAD = 1e18;

    /// @dev cache the routes for gas efficiency
    address internal immutable router;
    IPoolRegistry internal poolRegistry;
    IAgentPolice internal agentPolice;
    IAgentFactory internal agentFactory;

    /// @dev `id` is a cache of the Pool's ID for gas efficiency
    uint256 public immutable id;

    /// @dev `asset` is the token that is being borrowed in the pool (WFIL)
    IERC20 public immutable asset;

    /// @dev `liquidStakingToken` is the token that represents a liquidStakingToken in the pool
    IPoolToken public immutable liquidStakingToken;

    /// @dev `rateModule` is a separate module for computing rates and determining lending eligibility
    IRateModule public rateModule;

    /// @dev `prestake` is the address of the prestake contract
    IPreStake public immutable preStake;

    /// @dev `feesCollected` is the total fees collected in this pool
    uint256 public feesCollected = 0;

    /// @dev `totalBorrowed` is the total amount borrowed in this pool
    uint256 public totalBorrowed = 0;

    /// @dev `minimumLiquidity` is the percentage of total assets that should be reserved for exits
    uint256 public minimumLiquidity = 0;

    /// @dev `accruedRentalFees` tracks the amount of fees accrued based on borrowed FIL in the pool
    uint256 public accruedRentalFees = 0;

    /// @dev `paidRentalFees` tracks the amount of fees paid to this pool
    uint256 public paidRentalFees = 0;

    /// @dev `lostAssets` tracks the amount of assets that were lost as a result of a liquidation
    uint256 public lostAssets = 0;

    /// @dev `lastAccountingUpdatingEpoch` is the epoch at which the pool's accounting was last updated
    uint256 public lastAccountingUpdatingEpoch = 0;

    /// @dev `rentalFeesOwedPerEpoch` is the % of FIL charged to Agents on a per epoch basis
    uint256 public rentalFeesOwedPerEpoch = FixedPointMathLib.divWadDown(15e16, EPOCHS_IN_YEAR*1e18);

    /// @dev `isShuttingDown` is a boolean that, when true, halts deposits and borrows. Once set, it cannot be unset.
    bool public isShuttingDown = false;

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

    modifier onlyPoolRegistry() {
        _onlyPoolRegistry();
        _;
    }

    modifier isOpen() {
        _isOpen();
        _;
    }

    /*////////////////////////////////////////////////////////
                      Payable Fallbacks
    ////////////////////////////////////////////////////////*/

    /// @dev the pool can receive FIL from the WFIL.Withdraw method,
    /// so we make sure to not trigger a deposit in those cases
    /// (when this contract unwraps FIL triggering a receive or fallback)
    receive() isOpen external payable {
        if (msg.sender != address(asset)) _depositFIL(msg.sender);
    }

    fallback() isOpen external payable {
        if (msg.sender != address(asset)) _depositFIL(msg.sender);
    }

    // The only things we need to pull into this contract are the ones unique to _each pool_
    // This is just the approval module, and the treasury address
    // Everything else is accesible through the router (power token for example)
    constructor(
        address _owner,
        address _router,
        address _asset,
        address _rateModule,
        address _liquidStakingToken,
        address _preStake,
        uint256 _minimumLiquidity,
        uint256 _id
    ) Ownable(_owner) {
        router = _router;
        asset = IERC20(_asset);
        rateModule = IRateModule(_rateModule);
        preStake = IPreStake(_preStake);
        minimumLiquidity = _minimumLiquidity;
        // set the ID
        id = _id;
        // deploy a new liquid staking token for the pool
        liquidStakingToken = IPoolToken(_liquidStakingToken);

        poolRegistry = GetRoute.poolRegistry(router);
        agentPolice = GetRoute.agentPolice(router);
        agentFactory = GetRoute.agentFactory(router);
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
        return AccountHelpers.getAccount(router, agentID, id).principal;
    }

    /**
     * @dev Returns the totalAssets of the pool
     * @return totalBorrowed The total borrowed from the agent
     */
    function totalAssets() public view override returns (uint256) {
        // using accrual basis accounting, the assets of the pool are:
        // assets currently in the pool
        // total borrowed from agents
        // total accrued rental fees
        // subtract total rental fees paid
        // subtract lost assets from liquidations
        // subtract total treasury fees collected
        return asset.balanceOf(address(this)) 
          + totalBorrowed 
          + accruedRentalFees 
          - paidRentalFees 
          - lostAssets 
          - feesCollected;
    }

    /**
     * @dev Returns the amount of assets in the Pool that Agents can borrow
     * @return totalBorrowed The total borrowed from the agent
     */
    function totalBorrowableAssets() public view returns (uint256) {
        if (isShuttingDown) return 0;
        uint256 _assets = asset.balanceOf(address(this)) - feesCollected;
        uint256 _absMinLiquidity = getAbsMinLiquidity();

        if (_assets < _absMinLiquidity) return 0;
        return _assets - _absMinLiquidity;
    }

    /**
     * @dev Returns the amount of FIL the Pool aims to keep in reserves at the current epoch
     * @return minLiquidity The minimum amount of FIL to keep in reserves
     */
    function getAbsMinLiquidity() public view returns (uint256) {
        return (totalAssets().mulWadUp(minimumLiquidity));
    }

    /**
     * @dev Returns the amount of FIL the Pool aims to keep in reserves at the current epoch
     * @return liquidFunds The amount of total liquid assets held in the Pool
     */
    function getLiquidAssets() public view returns (uint256) {
        uint256 balance = asset.balanceOf(address(this));
        // ensure we dont pay out treasury fees
        if (balance <= feesCollected) return 0;

        return balance - feesCollected;
    }

    /**
     * @notice getRate returns the rate for an Agent's current position within the Pool
     * @return rate The rate for the Agent's current position and base rate
     */
    function getRate(
        VerifiableCredential calldata
    ) public view returns (uint256 rate) {
        return rentalFeesOwedPerEpoch;
    }

    /**
     * @notice isApproved returns false if the Agent is in an rejected state as determined by the rate module
     * @param account The Agent's account
     * @param vc The Agent's VerifiableCredential
     * @return approved Whether the Agent is approved
     * @dev approval criteria are determined by the `rateModule`
     */
    function isApproved(
        Account calldata account,
        VerifiableCredential calldata vc
    ) external view returns (bool approved) {
        return rateModule.isApproved(account, vc);
    }

    /**
     * @notice writeOff writes down the Agent's account and the Pool's borrowed amount after a liquidation
     * @param agentID The ID of the Agent
     * @param recoveredFunds The amount of funds recovered from the liquidation. This is the total amount the Police was able to recover from the Agent's Miner Actors
     * @dev the treasury fees go unpaid on a writeOff
     // TODO fix return value with agent police fix 
     */
    function writeOff(uint256 agentID, uint256 recoveredFunds) external returns (uint256) {
        // only the agent police can call this function
        _onlyAgentPolice();

        updateAccounting();

        Account memory account = _getAccount(agentID);

        if (account.defaulted) revert AlreadyDefaulted();
        // set the account to defaulted
        account.defaulted = true;

        uint256 interestOwed = 0;
        // if the account is not "current", compute the amount of interest owed based on the penalty rate
        if (account.epochsPaid < block.number) {
            interestOwed = account.principal.mulWadUp(rentalFeesOwedPerEpoch).mulWadUp(block.number - account.epochsPaid);
        }

        // compute the amount of fees and principal we can pay off
        uint256 totalOwed = interestOwed + account.principal;
        // the amount of fees that will be paid
        uint256 feeBasis = 0;
        // the amount of principal that will be paid
        uint256 principalPaid = 0;
        // the amount of funds that will be refunded to the agent
        uint256 remainder = 0;
        // the amount of funds that was lost in this write-off
        uint256 lost = 0;
        if (recoveredFunds <= interestOwed) {
          // if we can't cover the whole interest payment, we cover what we can
          feeBasis = recoveredFunds;
          // we lost the full principal + unpaid interest
          lost = account.principal + interestOwed - recoveredFunds;
        } else if (recoveredFunds <= totalOwed) {
          // if we can't cover the whole total owed, we apply everything to interest first
          feeBasis = interestOwed;
          // cover any principal with the remainder
          principalPaid = recoveredFunds - interestOwed;
          // we lost the unpaid principal
          lost = account.principal - principalPaid;
        } else {
          // we can cover everything
          feeBasis = interestOwed;
          principalPaid = account.principal;
          remainder = recoveredFunds - totalOwed;
          // we lost nothing
        }

        // write off the pool's account so that the pool's total borrowed is accurate
        totalBorrowed -= account.principal;
        // since this account's principal still accrues debt up to this point in time, we need to update the paidRentalFees one last time
        paidRentalFees += feeBasis;
        // add the lost assets to the pool's lost assets
        lostAssets += lost;
        // set the account with the funds the pool lost, this isn't used anywhere else in the protocol, just for querying later
        account.principal = lost;
        // pull in only the assets we need
        asset.transferFrom(msg.sender, address(this), feeBasis + principalPaid);

        account.save(router, agentID, id);

        emit WriteOff(agentID, recoveredFunds, lost, feeBasis);
        // TODO: Fixme
        return 0;
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
    function borrow(VerifiableCredential calldata vc) external isOpen subjectIsAgentCaller(vc) {
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
            poolRegistry.addPoolToList(vc.subject, id);
        }

        account.principal += vc.value;
        account.save(router, vc.subject, id);

        totalBorrowed += vc.value;

        emit Borrow(vc.subject, vc.value);

        // interact - here `msg.sender` must be the Agent bc of the `subjectIsAgentCaller` modifier
        asset.transfer(msg.sender, vc.value);
    }

    /**
     * @notice pay handles the accounting for a payment from the Agent to the Infintiy Pool
     * @param vc The Agent's VerifiableCredential - the `subject` must be the Agent's ID and the `value` must be the amount to pay
     * @return rate The dynamic rate applied to this payment
     * @return epochsPaid The number of epochs to move the account forward after payment
     * @return principalPaid The amount of principal paid down (could be 0 if interest only payment)
     * @return refund The amount of funds to refund to the Agent (could be 0 if no overpayment)
     * @dev The pay function applies the payment amount to the interest owed on the account first. If the entire interest owed is paid off by the payment, then the remainder is applied to the principal owed on the account.
     * @dev Treasury fees only apply to interest payments, not principal payments
     */
    function pay(
        VerifiableCredential calldata vc
    ) external subjectIsAgentCaller(vc) returns (
        uint256 rate,
        uint256 epochsPaid,
        uint256 principalPaid,
        uint256 refund
    ) {
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
        if (account.defaulted) {
            // accrue treasury fee
            feesCollected += poolRegistry.treasuryFeeRate().mulWadUp(vc.value);
            // here we explicitly do not update the paidRentalFees 
            // transfer the assets into the pool
            asset.transferFrom(msg.sender, address(this), vc.value);

            emit Pay(vc.subject, rentalFeesOwedPerEpoch, 0, 0, 0);

            return (rentalFeesOwedPerEpoch, account.epochsPaid, 0, 0);
        }

        // if the account is not "current", compute the amount of interest owed based on the new rate
        if (account.epochsPaid < block.number) {
            // compute the number of epochs that are owed to get current
            uint256 epochsToPay = block.number - account.epochsPaid;
            // multiply the rate by the principal to get the per epoch interest rate
            // the interestPerEpoch has an extra WAD to maintain precision
            interestPerEpoch = account.principal.mulWadUp(rentalFeesOwedPerEpoch);
            // ensure the payment is greater than or equal to at least 1 epochs worth of interest
            // NOTE - we multiply by WAD here because the interestPerEpoch has an extra WAD to maintain precision
            if (vc.value * WAD < interestPerEpoch) revert InvalidParams();
            // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
            // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
            interestOwed = interestPerEpoch.mulWadUp(epochsToPay);
        }
        // if the payment is less than the interest owed, pay interest only
        if (vc.value <= interestOwed) {
            // compute the amount of epochs this payment covers
            // vc.value is not WAD yet, so divWadDown cancels the extra WAD in interestPerEpoch
            uint256 epochsForward = vc.value.divWadDown(interestPerEpoch);
            // update the account's `epochsPaid` cursor
            account.epochsPaid += epochsForward;
            // since the entire payment is interest, the entire payment is used to compute the fee (principal payments are fee-free)
            feeBasis = vc.value;
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
                // remove the account from the pool's list of accounts
                poolRegistry.removePoolFromList(vc.subject, id);
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
        account.save(router, vc.subject, id);
        // realize fees paid to the pool
        paidRentalFees += feeBasis;
        // accrue treasury fees
        feesCollected += poolRegistry.treasuryFeeRate().mulWadUp(feeBasis);
        // transfer the assets into the pool
        asset.transferFrom(msg.sender, address(this), vc.value - refund);

        emit Pay(vc.subject, rate, account.epochsPaid, principalPaid, refund);

        return (rate, account.epochsPaid, principalPaid, refund);
    }

    /**
     * @dev Updates the accrual basis accounting of the pool
     */
    function updateAccounting() public {
      // only update the accounting if we're in a new epoch
      if (block.number > lastAccountingUpdatingEpoch) {
        accruedRentalFees += _computeNewFeesAccrued();
        lastAccountingUpdatingEpoch = block.number;
      }
    }

    function _computeNewFeesAccrued() internal view returns (uint256) {
      // only update the accounting if we're in a new epoch
      if (block.number > lastAccountingUpdatingEpoch) {
        // calculate the number of blocks passed since the last upgrade
        uint256 blocksPassed = block.number - lastAccountingUpdatingEpoch;
        // calculate the total % owed to the pool
        uint256 feeRateAccrued = rentalFeesOwedPerEpoch.mulWadUp(blocksPassed);
        // calculate the total interest accrued during this period
        return totalBorrowed.mulWadUp(feeRateAccrued);
      }
      return 0;
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
    function deposit(uint256 assets, address receiver) public isOpen returns (uint256 shares) {
        return _deposit(assets, receiver);
    }

    /**
     * @dev Allows Staker to deposit native FIL and receive shares in return
     * @param receiver The address that will receive the shares
     * @return shares - the number of shares received in exchange for the deposit
     */
    function deposit(address receiver) public payable isOpen returns (uint256 shares) {
        return _depositFIL(receiver);
    }

    /**
     * @dev Allows Staker to specify the number of `shares` to mint from the Pool by depositing `assets`
     * @param shares Number of shares to mint
     * @param receiver The address to receive the shares
     * @return assets Number of assets deposited
     */
    function mint(uint256 shares, address receiver) public isOpen returns (uint256 assets) {
        updateAccounting();
        // These transfers need to happen before the mint, and this is forcing a higher degree of coupling than is ideal
        assets = previewMint(shares);
        if(assets == 0 || shares == 0) revert InvalidParams();
        asset.transferFrom(msg.sender, address(this), assets);
        liquidStakingToken.mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @notice Allows Staker to withdraw assets
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public isOpen returns (uint256 shares) {
        updateAccounting();
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, false);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Allows the Staker to redeem their shares for assets
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public isOpen returns (uint256 assets) {
        updateAccounting();
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, false);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Allows Staker to withdraw assets (FIL)
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdrawF(
        uint256 assets,
        address receiver,
        address owner
    ) public isOpen ownerIsCaller(owner) returns (uint256 shares) {
        shares = previewWithdraw(assets);
        _processExit(owner, receiver, shares, assets, true);
    }

    /**
     * @notice Allows the Staker to redeem their shares for assets (FIL)
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeemF(
        uint256 shares,
        address receiver,
        address owner
    ) public isOpen ownerIsCaller(owner) returns (uint256 assets) {
        assets = previewRedeem(shares);
        _processExit(owner, receiver, shares, assets, true);
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
    function previewDeposit(uint256 assets) public view isOpen returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @notice Previews an amount of assets that would be needed to mint `shares`
     * @param shares The amount of shares to mint
     * @return assets - The amount of assets that would be converted from shares
     * @dev Will revert if the pool is shutting down
     */
    function previewMint(uint256 shares) public view isOpen returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @notice Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets) public view isOpen returns (uint256 shares) {
        if (assets > getLiquidAssets()) return 0;

        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        shares = supply == 0
            ? assets
            : assets.mulDivUp(supply, totalAssets());
    }

    /**
     * @notice Previews an amount of assets to redeem for a given number of `shares`
     * @param shares The amount of shares to hypothetically burn
     * @return assets - The amount of assets that would be converted from shares
     */
    function previewRedeem(uint256 shares) public view isOpen returns (uint256 assets) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        assets = supply == 0
            ? shares
            : shares.mulDivUp(totalAssets(), supply);
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
     * @dev Distributes feesCollected to the treasury
     */
    function harvestFees(uint256 harvestAmount) public {
        updateAccounting();
        feesCollected -= harvestAmount;
        asset.transfer(GetRoute.treasury(router), harvestAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    /**
     * @notice decomissionPool shuts down the pool and transfers all assets to the new pool
     * @param newPool The address of new pool to transfer assets to
     */
    function decommissionPool(
        IPool newPool
    ) external onlyPoolRegistry returns(uint256 borrowedAmount) {
      if (newPool.id() != id || !isShuttingDown) revert InvalidState();
        // forward fees to the treasury
        harvestFees(feesCollected);

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
    function jumpStartTotalBorrowed(uint256 amount) external onlyPoolRegistry {
        if (totalBorrowed != 0) revert InvalidState();
        totalBorrowed = amount;
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
        account.save(router, agentID, id);
        // add the pool to the agent's list of borrowed pools
        poolRegistry.addPoolToList(agentID, id);
        // mint the iFIL to the receiver, using principal as the deposit amount
        liquidStakingToken.mint(receiver, convertToShares(accountPrincipal));
        // account for the new principal in the total borrowed of the pool
        totalBorrowed += accountPrincipal;
    }

    /**
     * @notice setMinimumLiquidity sets the liquidity reserve threshold used for exits
     */
    function setMinimumLiquidity(uint256 _minimumLiquidity) external onlyOwner {
        minimumLiquidity = _minimumLiquidity;
    }

    /**
     * @notice shutDown sets the isShuttingDown variable to true, effectively halting all deposits and borrows
     */
    function shutDown() external onlyOwner {
        updateAccounting();
        isShuttingDown = true;
    }

    /**
     * @notice setRateModule sets the address of the rate module in storage
     */
    function setRateModule(IRateModule _rateModule) external onlyOwner {
        rateModule = _rateModule;
    }

    /**
     * @notice Transfers assets from the pre-stake contract to the pool, without minting new iFIL
     * @param _amount The amount of WFIL to transfer
     */
    function transferFromPreStake(uint256 _amount) external onlyOwner {
        asset.transferFrom(address(preStake), address(this), _amount);
    }

    /**
     * @notice refreshRoutes refreshes the pool's cached routes
     */
    function refreshRoutes() external {
        poolRegistry = GetRoute.poolRegistry(router);
        agentPolice = GetRoute.agentPolice(router);
        agentFactory = GetRoute.agentFactory(router);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccount(uint256 agent) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agent, id);
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

        emit Deposit(msg.sender, receiver.normalize(),  msg.value, lstAmount);
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
        if (
            vc.subject == 0 ||
            agentFactory.agents(msg.sender) != vc.subject
        ) revert Unauthorized();
    }

    function _isOpen() internal view {
        if (isShuttingDown) revert InvalidState();
    }

    function _onlyPoolRegistry() internal view {
        if (address(poolRegistry) != msg.sender) revert Unauthorized();
    }

    function _onlyAgentPolice() internal view {
        if (address(agentPolice) != msg.sender) revert Unauthorized();
    }
}

