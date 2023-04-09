// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.17;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {FilAddress} from "shim/FilAddress.sol";

import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {Agent} from "src/Agent/Agent.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {AccountHelpers} from "src/Pool/Account.sol";

import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_CRED_PARSER} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";

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

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 immutable WAD = 1e18;

    address public immutable router;

    /// @dev `id` is a cache of the Pool's ID for gas efficiency
    uint256 public immutable id;

    /// @dev `asset` is the token that is being borrowed in the pool
    IERC20 public immutable asset;

    /// @dev `liquidStakingToken` is the token that represents a liquidStakingToken in the pool
    IPoolToken public immutable liquidStakingToken;

    /// @dev `rateModule` is a separate module for computing rates and determining lending eligibility
    IRateModule public rateModule;

    /// @dev `ramp` is the interface that handles off-ramping
    IOffRamp public ramp;

    /// @dev `feesCollected` is the total fees collected in this pool
    uint256 public feesCollected = 0;

    /// @dev `totalBorrowed` is the total amount borrowed in this pool
    uint256 public totalBorrowed = 0;

    /// @dev `minimumLiquidity` is the percentage of total assets that should be reserved for exits
    uint256 public minimumLiquidity = 0;

    /// @dev `isShuttingDown` is a boolean that, when true, halts deposits and borrows. Once set, it cannot be unset.
    bool public isShuttingDown = false;

    /*//////////////////////////////////////////////////////////////
                              MODIFIERs
    //////////////////////////////////////////////////////////////*/

    modifier requiresRamp() {
        if (address(ramp) == address(0)) revert InvalidState();
        _;
    }

    /// @dev a modifier that ensures the caller matches the `vc.subject` and that the caller is an agent
    modifier subjectIsAgentCaller(VerifiableCredential memory vc) {
        if (
            GetRoute.agentFactory(router).agents(msg.sender) != vc.subject
        ) revert Unauthorized();
        _;
    }

    modifier onlyPoolRegistry() {
        AuthController.onlyPoolRegistry(router, msg.sender);
        _;
    }

    modifier isOpen() {
        if (isShuttingDown) revert PoolShuttingDown();
        _;
    }

    /*////////////////////////////////////////////////////////
                      Payable Fallbacks
    ////////////////////////////////////////////////////////*/

    receive() external payable {
        _depositFIL(msg.sender);
    }

    fallback() external payable {
        _depositFIL(msg.sender);
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
        uint256 _minimumLiquidity,
        uint256 _id
    ) Ownable(_owner) {
        router = _router;
        asset = IERC20(_asset);
        rateModule = IRateModule(_rateModule);
        minimumLiquidity = _minimumLiquidity;
        // set the ID
        id = _id;
        // deploy a new liquid staking token for the pool
        liquidStakingToken = IPoolToken(_liquidStakingToken);
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
        return asset.balanceOf(address(this)) + totalBorrowed - feesCollected;
    }

    /**
     * @dev Returns the amount of assets in the Pool that Agents can borrow
     * @return totalBorrowed The total borrowed from the agent
     */
    function totalBorrowableAssets() public view returns (uint256) {
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
        return (totalAssets() * minimumLiquidity / WAD);
    }

    /**
     * @dev Returns the amount of FIL the Pool aims to keep in reserves at the current epoch
     * @return liquidFunds The amount of total liquid assets held in the Pool
     */
    function getLiquidAssets() public view returns (uint256) {
        if(isShuttingDown) return 0;
        // This will throw if there is no excess liquidity due to underflow

        uint256 balance = asset.balanceOf(address(this));
        // ensure we dont pay out treasury fees
        if (balance <= feesCollected) return 0;

        return balance -= feesCollected;
    }

    /**
     * @notice getRate returns the rate for an Agent's current position within the Pool
     * @param vc The Agent's VerifiableCredential
     * @return rate The rate for the Agent's current position and base rate
     * @dev rate is determined by the `rateModule`
     */
    function getRate(
        VerifiableCredential memory vc
    ) public view returns (uint256 rate) {
        return rateModule.getRate(vc);
    }

    /**
     * @notice isApproved returns false if the Agent is in an rejected state as determined by the rate module
     * @param account The Agent's account
     * @param vc The Agent's VerifiableCredential
     * @return approved Whether the Agent is approved
     * @dev approval criteria are determined by the `rateModule`
     */
    function isApproved(
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (bool approved) {
        return rateModule.isApproved(account, vc);
    }

    /**
     * @notice writeOff writes down the Agent's account and the Pool's borrowed amount after a liquidation
     * @param agentID The ID of the Agent
     * @param recoveredFunds The amount of funds recovered from the liquidation. This is the total amount the Police was able to recover from the Agent's Miner Actors
     * @dev If `recoveredFunds` > `principal` owed on the Agent's account, then the remaining amount gets applied as interest according to a penalty rate
     */
    function writeOff(uint256 agentID, uint256 recoveredFunds) external {
        // only the agent police can call this function
        AuthController.onlyAgentPolice(router, msg.sender);

        Account memory account = _getAccount(agentID);

        if (account.defaulted) revert AlreadyDefaulted();
        // set the account to defaulted
        account.defaulted = true;
        // amount of principal owed to this pool
        uint256 principalOwed = account.principal;
        // compute the amount of funds > principal that can be applied towards interest
        uint256 remainder = recoveredFunds > principalOwed ? recoveredFunds - principalOwed : 0;
        // compute the amount of interest owed on the account, based on a penalty rate
        uint256 interestPaid;
        // if the account is not "current", compute the amount of interest owed based on the penalty rate
        if (remainder > 0 && account.epochsPaid < block.number) {
            // compute a rate based on the agent's current financial situation
            uint256 rate = rateModule.penaltyRate();
            // compute the number of epochs that are owed to get current
            uint256 epochsToPay = block.number - account.epochsPaid;
            // multiply the rate by the principal to get the per epoch interest rate
            // the interestPerEpoch has an extra WAD to maintain precision
            // compute the total interest owed by multiplying how many epochs to pay, by the per epoch interest payment
            // using WAD math here ends up canceling out the extra WAD in the interestPerEpoch
            uint256 interestOwed = principalOwed.mulWadUp(rate).mulWadUp(epochsToPay);
            // compute the amount of interest to pay down
            interestPaid = interestOwed > remainder ? remainder : interestOwed;
            // collect fees on the interest paid
            feesCollected += GetRoute
                .poolRegistry(router)
                .treasuryFeeRate()
                // only charge on the actual interest paid
                .mulWadUp(interestPaid);
        }

        // transfer the assets into the pool
        // whatever we couldn't pay back
        uint256 lostAmt = principalOwed > recoveredFunds ? principalOwed - recoveredFunds : 0;

        uint256 totalOwed = interestPaid + principalOwed;

        asset.transferFrom(
          msg.sender,
          address(this),
          totalOwed > recoveredFunds ? recoveredFunds : totalOwed
        );
        // write off only what we lost
        totalBorrowed -= lostAmt;
        // set the account with the funds the pool lost
        account.principal = lostAmt;

        account.save(router, agentID, id);

        emit WriteOff(agentID, recoveredFunds, lostAmt, interestPaid);
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
    function borrow(VerifiableCredential memory vc) external isOpen subjectIsAgentCaller(vc) {
        // 1e18 => 1 FIL, can't borrow less than 1 FIL
        if (vc.value < WAD) revert InvalidParams();
        // can't borrow more than the pool has
        if (totalBorrowableAssets() < vc.value) revert InsufficientLiquidity();
        Account memory account = _getAccount(vc.subject);
        // fresh account, set start epoch and epochsPaid to beginning of current window
        if (account.principal == 0) {
            uint256 currentEpoch = block.number;
            account.startEpoch = currentEpoch;
            account.epochsPaid = currentEpoch;
            GetRoute.agentPolice(router).addPoolToList(vc.subject, id);
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
        VerifiableCredential memory vc
    ) external subjectIsAgentCaller(vc) returns (
        uint256 rate,
        uint256 epochsPaid,
        uint256 principalPaid,
        uint256 refund
    ) {
        // grab this Agent's account from storage
        Account memory account = _getAccount(vc.subject);
        // ensure we're not making payments to a non-existent account
        if (!account.exists()) revert AccountDNE();
        // compute a rate based on the agent's current financial situation
        rate = getRate(vc);
        // the total interest amount owed to get the epochsPaid cursor to the current epoch
        uint256 interestOwed;
        // rate * principal, used for computing the interest owed and moving the epochsPaid cursor
        uint256 interestPerEpoch;
        // the amount of interest paid on this payment, used for computing the treasury fee
        uint256 feeBasis;

        // if the account is not "current", compute the amount of interest owed based on the new rate
        if (account.epochsPaid < block.number) {
            // compute the number of epochs that are owed to get current
            uint256 epochsToPay = block.number - account.epochsPaid;
            // multiply the rate by the principal to get the per epoch interest rate
            // the interestPerEpoch has an extra WAD to maintain precision
            interestPerEpoch = account.principal.mulWadUp(rate);
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
            // pay interest and principal
            principalPaid = vc.value - interestOwed;
            // the fee basis only applies to the interest payment
            feeBasis = interestOwed;
            // protect against underflow
            totalBorrowed -= (principalPaid > totalBorrowed) ? 0 : principalPaid;
            // fully paid off
            if (principalPaid >= account.principal) {
                // remove the account from the pool's list of accounts
                GetRoute.agentPolice(router).removePoolFromList(vc.subject, id);
                // return the amount of funds overpaid
                refund = principalPaid - account.principal;
                // reset the account
                account.reset();
            } else {
                // interest and partial principal payment
                account.principal -= principalPaid;
                // move the `epochsPaid` cursor to mark the account as "current"
                account.epochsPaid = block.number;
            }

        }
        // update the account in storage
        account.save(router, vc.subject, id);
        // accrue treasury fee
        feesCollected += GetRoute
            .poolRegistry(router)
            .treasuryFeeRate()
            .mulWadUp(feeBasis);

        // transfer the assets into the pool
        asset.transferFrom(msg.sender, address(this), vc.value - refund);

        emit Pay(vc.subject, rate, account.epochsPaid, principalPaid, refund);

        return (rate, account.epochsPaid, principalPaid, refund);
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
     * @dev Allows Staker to mint `shares` into the Pool to receive `assets`
     * @param shares Number of shares to mint
     * @param receiver The address to receive the shares
     * @return assets Number of assets deposited
     */
    function mint(uint256 shares, address receiver) public isOpen returns (uint256 assets) {
        if(shares == 0) revert InvalidParams();
        // These transfers need to happen before the mint, and this is forcing a higher degree of coupling than is ideal
        assets = previewMint(shares);
        asset.transferFrom(msg.sender, address(this), assets);
        liquidStakingToken.mint(receiver, shares);
        assets = convertToAssets(shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Allows Staker to withdraw assets
     * @param assets The assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return shares - the number of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public requiresRamp returns (uint256 shares) {
        shares = ramp.withdraw(assets, receiver, owner, totalAssets());
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @dev Allows the Staker to redeem their shares for assets
     * @param shares The number of shares to burn
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The assets received from burning the shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public requiresRamp returns (uint256 assets) {
        assets = ramp.redeem(shares, receiver, owner, totalAssets());
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

        return supply == 0 ? assets : assets * supply / totalAssets();
    }

    /**
     * @dev Converts `shares` to assets
     * @param shares The amount of shares to convert
     * @return assets - The amount of assets converted from shares
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares * totalAssets() / supply;
    }

    /**
     * @dev Previews an amount of shares that would be received for depositing `assets`
     * @param assets The amount of assets to preview deposit
     * @return shares - The amount of shares that would be converted from assets
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    /**
     * @dev Previews an amount of assets that would be needed to mint `shares`
     * @param shares The amount of shares to mint
     * @return assets - The amount of assets that would be converted from shares
     */
    function previewMint(uint256 shares) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares * totalAssets() / supply;
    }

    /**
     * @dev Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets * supply / totalAssets();
    }

    /**
     * @dev Previews an amount of assets to redeem for a given number of `shares`
     * @param shares The amount of shares to hypothetically burn
     * @return assets - The amount of assets that would be converted from shares
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return convertToAssets(liquidStakingToken.balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return liquidStakingToken.balanceOf(owner);
    }


    /*//////////////////////////////////////////////////////////////
                            FEE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Distributes funds to the offramp when the liquid assets are below the liquidity threshold
     */
    function harvestToRamp() public requiresRamp {
        // distribute funds to the offramp when we are below the liquidity threshold
        uint256 exitDemand = ramp.totalIOUStaked();
        uint256 rampAssets = asset.balanceOf(address(ramp));

        // only send funds to the offramp if our liquidityReserves are less than the min liquidity reserve requirement
        if (rampAssets < exitDemand) {
            // distribute the difference between the min liquidity reserve requirement and our liquidity reserves
            // if our liquid funds are not enough to cover, send the max amount of funds
            uint256 toDistribute = Math.min(
                exitDemand - rampAssets,
                getLiquidAssets()
            );
            asset.approve(address(ramp), toDistribute);
            ramp.distribute(address(this), toDistribute);
        }
    }

    /**
     * @dev Distributes feesCollected to the treasury
     */
    function harvestFees(uint256 harvestAmount) public {
        feesCollected -= harvestAmount;
        asset.transfer(GetRoute.treasury(router), harvestAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice setRamp sets the address of the ramp in storage
     */
    function setRamp(IOffRamp _ramp) external onlyOwner {
        ramp = _ramp;
    }

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
        GetRoute.agentPolice(router).addPoolToList(agentID, id);
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
     * @notice shutDown sets the isShuttingDown variable to true, effectively halting all
     */
    function shutDown() external onlyOwner {
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
     * @param _preStake The address of the pre-stake contract
     * @param _amount The amount of WFIL to transfer
     */
    function transferFromPreStake(address _preStake, uint256 _amount) external onlyOwner {
        asset.transferFrom(_preStake, address(this), _amount);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccount(uint256 agent) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agent, id);
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 lstAmount) {
        if (assets == 0) revert InvalidParams();
        // get the number of iFIL tokens to mint
        lstAmount = previewDeposit(assets);
        // pull in the assets
        asset.transferFrom(msg.sender, address(this), assets);
        // mint the iFIL tokens
        liquidStakingToken.mint(receiver, lstAmount);

        emit Deposit(msg.sender, receiver.normalize(), assets, lstAmount);
    }

    function _depositFIL(address receiver) internal returns (uint256 lstAmount) {
        if (msg.value == 0) revert InvalidParams();

        IWFIL wFIL = GetRoute.wFIL(router);

        // handle FIL deposit
        wFIL.deposit{value: msg.value}();

        lstAmount = previewDeposit(msg.value);

        liquidStakingToken.mint(receiver, lstAmount);

        emit Deposit(msg.sender, receiver.normalize(),  msg.value, lstAmount);
    }
}

