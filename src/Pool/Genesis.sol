// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {Agent} from "src/Agent/Agent.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Operatable} from "src/Auth/Operatable.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {PoolToken} from "src/Pool/PoolToken.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {Window} from "src/Types/Structs/Window.sol";
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_CRED_PARSER} from "src/Constants/Routes.sol";
import {EPOCHS_IN_DAY} from "src/Constants/Epochs.sol";
import {console} from "forge-std/console.sol";

uint256 constant wad = 1e18;
contract GenesisPool is IPool, RouterAware, Operatable {
    using FixedPointMathLib for uint256;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;

    error InsufficientLiquidity();
    error AccountDNE();
    error Unauthorized();
    error InvalidParams();
    error PoolShuttingDown();
    error AlreadyDefaulted();

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev `id` is a cache of the Pool's ID for gas efficiency
    uint256 public immutable id;

    /// @dev `baseRate` sets the curve of the dynamic rate
    uint256 public baseRate;

    /// @dev `maxDTI` is the
    uint256 private maxDTI;

    /// @dev `asset` is the token that is being borrowed in the pool
    ERC20 public asset;

    /// @dev `liquidStakingToken` is the token that represents a liquidStakingToken in the pool
    PoolToken public liquidStakingToken;

    /// @dev `exitToken` is a pegged FIL token used for exiting with the ramp
    PoolToken public exitToken;

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

    uint256[] rateLookup = new uint256[](100);
    
    /*//////////////////////////////////////////////////////////////
                              MODIFIERs
    //////////////////////////////////////////////////////////////*/

    modifier requiresRamp() {
        require(address(ramp) != address(0), "No ramp set");
        _;
    }

    modifier onlyAgent() {
        AuthController.onlyAgent(router, msg.sender);
        _;
    }

    /// @dev a modifier that ensures the caller matches the `vc.subject` and that the caller is an agent
    modifier subjectIsAgentCaller(VerifiableCredential memory vc) {
        if (
            GetRoute.agentFactory(router).agents(msg.sender) != vc.subject
        ) revert Unauthorized();
        _;
    }

    modifier onlyAgentPolice() {
        AuthController.onlyAgentPolice(router, msg.sender);
        _;
    }

    modifier onlyPoolFactory() {
        AuthController.onlyPoolFactory(router, msg.sender);
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
        address _operator,
        address _router,
        address _asset,
        address _ramp,
        uint256 _minimumLiquidity,
        uint256 _baseRate,
        uint256 _maxDTI,
        uint256[100] memory _rateLookup
    ) Operatable(_owner, _operator) {
        router = _router;
        asset = ERC20(_asset);
        ramp = IOffRamp(_ramp);
        minimumLiquidity = _minimumLiquidity;
        baseRate = _baseRate;
        maxDTI = _maxDTI;
        rateLookup = _rateLookup;
        // set the ID
        id = GetRoute.poolFactory(router).allPoolsLength();
        // deploy a new liquid staking token for the pool
        liquidStakingToken = new PoolToken(
            _router,
            id,
            "Genesis Pool Staked FIL",
            "gstETH"
        );
        // deploy an exit token for the pool
        exitToken = new PoolToken(
            _router,
            id,
            "Genesis Pool Exit Token",
            "gexETH"
        );
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the amount a specific Agent has borrowed from this pool
     * @param agentID The ID of the agent
     * @return totalBorrowed The total borrowed from the agent
     */
    function getAgentBorrowed(uint256 agentID) public view returns (uint256) {
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
        return totalAssets().mulWadDown(minimumLiquidity);
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
    * rate is based on the formula base rate  e^(bias * (100 - GCRED)) where the exponent is pulled from a lookup table
    */
    function getRate(
        Account memory account,
        VerifiableCredential memory vc
    ) public view returns (uint256) {
        address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
        return (baseRate * rateLookup[vc.getGCRED(credParser)]) / wad;
    }

    // TODO: this is wrong, it needs fixed point math
    /**
     * @notice isOverLeveraged returns true if the Agent is over leveraged
     * In this version, an Agent can be over-leveraged in either of two cases:
     * 1. The Agent's principal is more than the equity weighted `agentTotalValue`
     * 2. The Agent's expected daily payment is more than `dtiWeight` of their income
     */
    function isOverLeveraged(
        Account memory account,
        VerifiableCredential memory vc
    ) external view returns (bool) {
        address credParser = IRouter(router).getRoute(ROUTE_CRED_PARSER);
        // equity percentage
        uint256 totalPrincipal = vc.getPrincipal(credParser);
        uint256 accountPrincipal = account.principal;
        // compute our pool's percentage of the agent's assets
        uint256 equityPercentage = (accountPrincipal * wad) / totalPrincipal;
        // If this pool has no equity in the agent, they are not over leveraged
        if(equityPercentage == 0) return false;
        uint256 agentTotalValue = vc.getAgentValue(credParser);
        // compute value used in LTV calculation
        // We leave the e18 in here so we don't have to add it back in when calculating LTV
        // If the agent's principal is greater than the value of their assets, they are over leveraged
        if(accountPrincipal > agentTotalValue) return true;
        uint256 poolShareOfValue = (equityPercentage * (agentTotalValue - accountPrincipal)) / wad;

        //NOTE: I would recommend just evaluating if poolShareOfValue > accountPrincipal it's functionally the same
        // if (poolShareOfValue < accountPrincipal) return true;
        // compute LTV (also wrong bc %)
        uint256 ltv = accountPrincipal * wad / poolShareOfValue;
        // if LTV is greater than 1 (e18 denominated), we are over leveraged (can't mortgage more than the value of your home)
        if (ltv > wad) return true;

        uint256 rate = getRate(account, vc);
        // compute expected daily payments to align with expected daily reward
        uint256 dailyRate = (rate * EPOCHS_IN_DAY * accountPrincipal) / wad;
        uint256 dailyRewards = vc.getExpectedDailyRewards(credParser);

        // compute DTI
        uint256 dti = dailyRate / dailyRewards;

        return dti > maxDTI;
    }

    function writeOff(uint256 agentID, uint256 recoveredDebt) external onlyAgentPolice {
        Account memory account = _getAccount(agentID);

        if (account.defaulted) revert AlreadyDefaulted();

        uint256 owed = account.principal;

        if (recoveredDebt > owed) recoveredDebt = owed;

        // transfer the assets into the pool
        SafeTransferLib.safeTransferFrom(
            asset,
            msg.sender,
            address(this),
            recoveredDebt
        );
        // whatever we couldn't pay back
        uint256 lostAmt = owed - recoveredDebt;
        // write off only what we lost
        totalBorrowed -= lostAmt;

        account.defaulted = true;

        account.save(router, agentID, id);

        emit WriteOff(agentID, recoveredDebt, lostAmt);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL BORROWING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function borrow(VerifiableCredential memory vc) external subjectIsAgentCaller(vc) {
        if (vc.value == 0) revert InvalidParams();

        // if (vc.action == borrow && !belowLimit) || vc.action == refinance {
        //     ...proceed
        // }

        _checkLiquidity(vc.value);
        Account memory account = _getAccount(vc.subject);
        // fresh account, set start epoch and epochsPaid to beginning of current window
        if (account.principal == 0) {
            uint256 currentEpoch = block.number;
            account.startEpoch = currentEpoch;
            account.epochsPaid = currentEpoch;
        }

        account.principal += vc.value;
        account.save(router, vc.subject, id);

        totalBorrowed += vc.value;

        emit Borrow(vc.subject, vc.value);

        // interact - here `msg.sender` must be the Agent bc of the `subjectIsAgentCaller` modifier
        SafeTransferLib.safeTransfer(asset, msg.sender, vc.value);
    }


    function pay(
        VerifiableCredential memory vc
    ) external returns (
        uint256 rate, uint256 epochsPaid, uint256 refund
    ) {
        // grab this Agent's account from storage
        Account memory account = _getAccount(vc.subject);
        // ensure we're not making payments to a non-existent account
        _accountExists(account);
        // compute a rate based on the agent's current financial situation
        rate = getRate(account, vc);
        uint256 interestOwed;
        uint256 feeBasis;

        // if the account is not "current", compute the amount of interest owed based on the new rate
        if (account.epochsPaid < block.number) {
            uint256 epochsToPay = block.number - account.epochsPaid;
            interestOwed = rate * epochsToPay;
        }
        // if the payment is less than the interest owed, pay interest only
        if (vc.value <= interestOwed) {
            // compute the amount of epochs this payment covers
            uint256 epochsForward = vc.value / rate;
            // update the account's `epochsPaid` cursor
            account.epochsPaid += epochsForward;
            // since the entire payment is interest, the entire payment is used to compute the fee (principal payments are fee-free)
            feeBasis = vc.value;
        } else {
            // pay interest and principal
            uint256 principalPaid = vc.value - interestOwed;
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
        // take fee
        feesCollected += GetRoute
            .poolFactory(router)
            .treasuryFeeRate()
            .mulWadUp(feeBasis);

        // transfer the assets into the pool
        SafeTransferLib.safeTransferFrom(
            asset,
            msg.sender,
            address(this),
            vc.value - refund
        );

        emit Pay(vc.subject, rate, account.epochsPaid, refund);

        return (rate, account.epochsPaid, refund);
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
        require(shares > 0, "Pool: cannot mint 0 shares");
        // These transfers need to happen before the mint, and this is forcing a higher degree of coupling than is ideal
        assets = previewMint(shares);
        SafeTransferLib.safeTransferFrom(ERC20(asset), msg.sender, address(this), assets);
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
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        liquidStakingToken.burn(owner, shares);

        // Handle minimum liquidity in case that PoolAccounting has sufficient balance to cover
        exitToken.mint(address(this), assets);
        exitToken.approve(address(ramp), assets);
        ramp.stakeOnBehalf(assets, receiver);
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

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        liquidStakingToken.burn(owner, shares);

        // Handle minimum liquidity in case that PoolAccounting has sufficient balance to cover
        exitToken.mint(address(this), assets);
        exitToken.approve(address(ramp), assets);
        ramp.stakeOnBehalf(assets, receiver);
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

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    /**
     * @dev Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = liquidStakingToken.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
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
    function harvestToRamp() public {
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
     * @dev Distributes funds to the offramp when the liquid assets are below the liquidity threshold
     *
     * @notice we piggy back the fee collection off a transaction once accrued fees reach the threshold value
     * anyone can call this function to send the fees to the treasury at any time
     */
    function harvestFees(uint256 harvestAmount) public {
        feesCollected -= harvestAmount;
        asset.transfer(GetRoute.treasury(router), harvestAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRamp(IOffRamp _ramp) external onlyOwnerOperator {
        ramp = _ramp;
    }

    function decommissionPool(
        IPool newPool
    ) public onlyPoolFactory returns(uint256 borrowedAmount) {
        require(isShuttingDown, "POOL: Must be shutting down");
        require(newPool.id() == id, "POOL: New pool must have same ID");
        harvestFees(feesCollected);
        asset.transfer(address(newPool), asset.balanceOf(address(this)));
        liquidStakingToken.transfer(address(newPool), liquidStakingToken.balanceOf(address(this)));
        exitToken.transfer(address(newPool), exitToken.balanceOf(address(this)));
        borrowedAmount = totalBorrowed;
    }

    function jumpStartTotalBorrowed(uint256 amount) public onlyPoolFactory {
        require(totalBorrowed == 0, "POOL: Total borrowed must be 0");
        totalBorrowed = amount;
    }

    function setMinimumLiquidity(uint256 _minimumLiquidity) public onlyOwnerOperator {
        minimumLiquidity = _minimumLiquidity;
    }

    function shutDown() public onlyOwnerOperator {
        isShuttingDown = true;
    }

    function setBaseRate(uint256 _baseRate) public onlyOwnerOperator {
        baseRate = _baseRate;
    }

    function setMaxDTI(uint256 _maxDTI) public onlyOwnerOperator {
        maxDTI = _maxDTI;
    }

    function setRateLookup(uint256[100] memory _rateLookup) public onlyOwnerOperator {
        rateLookup = _rateLookup;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addressToID(address agent) internal view returns (uint256) {
        return IAgent(agent).id();
    }

    function _getAccount(uint256 agent) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agent, id);
    }

    function _accountExists(
        Account memory account
    ) internal pure {
        if (!account.exists()) {
            revert AccountDNE();
        }
    }

    function _checkLiquidity(uint256 amount) internal view {
        uint256 available = totalBorrowableAssets();
        if (available < amount) {
            revert InsufficientLiquidity();
        }
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        require(assets > 0, "Pool: cannot deposit 0 assets");
        shares = previewDeposit(assets);
        SafeTransferLib.safeTransferFrom(ERC20(asset), msg.sender, address(this), assets);
        liquidStakingToken.mint(receiver, shares);
        assets = convertToAssets(shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _depositFIL(address receiver) internal returns (uint256 shares) {
        IWFIL wFIL = GetRoute.wFIL(router);

        // in this Pool, the asset must be wFIL
        require(
            address(asset) == address(wFIL),
            "Asset must be wFIL to deposit FIL"
        );
        // handle FIL deposit
        uint256 assets = msg.value;
        wFIL.deposit{value: assets}();
        wFIL.transfer(address(this), assets);
        require(assets > 0, "Pool: cannot deposit 0 assets");

        shares = previewDeposit(assets);
        liquidStakingToken.mint(receiver, shares);
        assets = convertToAssets(shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _computeFeePerPmt(uint256 pmt) internal view returns (uint256 fee) {
        // protocol fee % * pmt
        fee = GetRoute
            .poolFactory(router)
            .treasuryFeeRate()
            .mulWadUp(pmt);
    }
}

