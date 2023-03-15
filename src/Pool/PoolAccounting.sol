// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {Agent} from "src/Agent/Agent.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
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
import {IPoolImplementation} from "src/Types/Interfaces/IPoolImplementation.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN} from "src/Constants/Routes.sol";
import {InsufficientLiquidity} from "src/Errors.sol";

contract PoolAccounting is IPool, RouterAware, Operatable {
    using FixedPointMathLib for uint256;
    using AccountHelpers for Account;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev `id` is a cache of the Pool's ID for gas efficiency
    uint256 public immutable id;

    /// @dev `template`
    IPoolTemplate public template;

    /// @dev `implementation handles logic for approving borrow requests and setting rates/account health
    IPoolImplementation public implementation;

    /// @dev `asset` is the token that is being borrowed in the pool
    ERC20 public asset;

    /// @dev `share` is the token that represents a share in the pool
    PoolToken public share;

    /// @dev `iou` is the token that represents the IOU of a borrow
    PoolToken public iou;

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
        require(address(ramp) != address(0), "No ramp set");
        _;
    }

    modifier onlyAgent() {
        AuthController.onlyAgent(router, msg.sender);
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

    modifier onlyTemplate() {
        require(msg.sender == address(template), "onlyPoolTemplate: Not authorized");
        _;
    }

    modifier isOpen() {
        require(!isShuttingDown, "Pool is shutting down");
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
        uint256 _id,
        address _router,
        address _poolImplementation,
        address _asset,
        address _share,
        address _template,
        address _ramp,
        address _iou,
        uint256 _minimumLiquidity
    ) Operatable(_owner, _operator) {
        id = _id;
        router = _router;
        implementation = IPoolImplementation(_poolImplementation);
        template = IPoolTemplate(_template);
        share = PoolToken(_share);
        asset = ERC20(_asset);
        iou = PoolToken(_iou);
        ramp = IOffRamp(_ramp);
        asset.approve(_template, type(uint256).max);
        minimumLiquidity = _minimumLiquidity;
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
        return AccountHelpers.getAccount(router, agentID, id).totalBorrowed;
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

    /*//////////////////////////////////////////////////////////////
                      ONLY CALLABLE BY TEMPLATE
    //////////////////////////////////////////////////////////////*/


    // NOTE: Making these seperate saves us a step but maybe there's a smarter way to do this; feels wrong idk
    function reduceTotalBorrowed(uint256 amount) external onlyTemplate {
        totalBorrowed -= amount;
    }

    function increaseTotalBorrowed(uint256 amount) external onlyTemplate {
        totalBorrowed += amount;
    }

    /*//////////////////////////////////////////////////////////////
                        POOL BORROWING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows user to borrow asset
     * @param amount The amount of asset to borrow
     * @param sc The Agent's signed credential from the VC issuer
     * @param powerTokenAmount The amount of power tokens to pledge to the Pool
     */
    function borrow(
        uint256 amount,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    )
        public
        onlyAgent
        isOpen
    {
        // pull the powerTokens into the pool
        GetRoute.powerToken(router).transferFrom(msg.sender, address(this), powerTokenAmount);

        Account memory account = _getAccount(msg.sender);

        implementation.beforeBorrow(
            amount,
            powerTokenAmount,
            account,
            sc.vc
        );

        template.borrow(
            amount,
            sc.vc,
            powerTokenAmount,
            implementation,
            account
        );
        // interact
        SafeTransferLib.safeTransfer(asset, msg.sender, amount);
    }

    /**
     * @dev Makes a payment of `pmt` to the Pool
     * @param agent The address of the agent to credit the payment for
     * @param pmt The amount to pay
     */
    function makePayment(
        address agent,
        uint256 pmt
    ) public {
        Account memory account = _getAccount(agent);

        (,uint256 remainingPmt) = _accrueFees(pmt, account);

        implementation.beforeMakePayment(
            remainingPmt,
            account
        );

        template.makePayment(
            agent,
            account,
            remainingPmt
        );

        SafeTransferLib.safeTransferFrom(
            asset,
            msg.sender,
            address(this),
            remainingPmt
        );
    }
    /**
     * @dev Allows an agent to exit the pool and returns the powerTokens to the agent
     * @param agent The agent who is exiting (and where to send the `powerTokensToReturn`)
     * @param sc The signed credential of the agent
     * @param amount The amount of borrowed assets that the agent will return
     * @return powerTokensToReturn the amount of power tokens to return to the agent
     */
    function exitPool(
        address agent,
        SignedCredential memory sc,
        uint256 amount
    ) public onlyAgent returns (
        uint256 powerTokensToReturn
    ) {
        // Pull back the borrowed asset
        SafeTransferLib.safeTransferFrom(
            asset,
            agent,
            address(this),
            amount
        );

        Account memory account = _getAccount(agent);

        implementation.beforeExit(
            amount,
            account,
            sc.vc
        );

        powerTokensToReturn = template.exitPool(
            amount,
            sc.vc,
            AccountHelpers.getAccount(router, agent, id)
        );

        // Return the power tokens to the agent
        GetRoute.powerToken(router).transfer(sc.vc.subject, powerTokensToReturn);
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
        template.mint(shares, receiver);
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
        shares = template.withdraw(assets, receiver, owner, share, iou);
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
        assets = template.redeem(shares, receiver, owner, share, iou);
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
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    /**
     * @dev Converts `shares` to assets
     * @param shares The amount of shares to convert
     * @return assets - The amount of assets converted from shares
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    /**
     * @dev Rebalances the total borrowed amount after checking the actual value of an account
     * @param agentID The ID of the agent's account
     * @param realAccountValue The actual value of the account
     */
    function rebalanceTotalBorrowed(
        uint256 agentID,
        uint256 realAccountValue
    ) external onlyAgentPolice {
        uint256 prevAccountBorrowed = AccountHelpers.getAccount(router, agentID, id).totalBorrowed;

        // rebalance the books
        if (realAccountValue > prevAccountBorrowed) {
            // we have more assets than we thought
            // here we just write up to the actual account borrowed amount
            totalBorrowed += prevAccountBorrowed;
        } else {
            // we have less assets than we thought
            // so we write down the diff of what we actually have from what we thought we had
            totalBorrowed -= (prevAccountBorrowed - realAccountValue);
        }

        emit RebalanceTotalBorrowed(agentID, realAccountValue, totalBorrowed);
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
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    /**
     * @dev Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

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
        return convertToAssets(share.balanceOf(owner));
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return share.balanceOf(owner);
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
        IPowerToken powerToken = GetRoute.powerToken(router);
        powerToken.transfer(address(newPool), powerToken.balanceOf(address(this)));
        asset.transfer(address(newPool), asset.balanceOf(address(this)));
        share.transfer(address(newPool), share.balanceOf(address(this)));
        iou.transfer(address(newPool), iou.balanceOf(address(this)));
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

    function setTemplate(IPoolTemplate poolTemplate) public onlyOwnerOperator {
        require(
            GetRoute.poolFactory(router).isPoolTemplate(address(poolTemplate)),
            "Pool: Invalid template"
        );
        template = poolTemplate;
    }

    function setImplementation(IPoolImplementation poolImplementation) public onlyOwnerOperator {
        require(
            GetRoute.poolFactory(router).isPoolImplementation(address(poolImplementation)),
            "Pool: Invalid implementation"
        );
        implementation = poolImplementation;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _addressToID(address agent) internal view returns (uint256) {
        return IAgent(agent).id();
    }

    function _getAccount(address agent) internal view returns (Account memory) {
        return AccountHelpers.getAccount(router, agent, id);
    }

    function _accrueFees(
        uint256 pmt,
        Account memory account
    ) internal returns (
        uint256 fee, uint256 remainingPmt
    ) {
        IPoolFactory poolFactory = GetRoute.poolFactory(router);

        (fee, remainingPmt) = account.computeFeePerPmt(pmt, poolFactory.treasuryFeeRate());

        feesCollected += fee;

        // harvest when our Max(liquidAssets, feesCollected) surpass our fee harvest threshold
        uint256 liquidAssets = asset.balanceOf(address(this));
        uint256 harvestAmount = feesCollected > liquidAssets
            ? liquidAssets : feesCollected;
        if (harvestAmount >= poolFactory.feeThreshold()) {
            harvestFees(harvestAmount);
        }
    }

    function _deposit(uint256 assets, address receiver) internal returns (uint256 shares) {
        require(assets > 0, "Pool: cannot deposit 0 assets");
        shares = previewDeposit(assets);
        SafeTransferLib.safeTransferFrom(ERC20(asset), msg.sender, address(this), assets);
        template.mint(shares, receiver);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function _depositFIL(address receiver) internal returns (uint256 shares) {
        uint256 assets = template.filToAsset{value: msg.value}(asset, address(this));
        require(assets > 0, "Pool: cannot deposit 0 assets");

        shares = previewDeposit(assets);
        template.mint(shares, receiver);
        emit Deposit(msg.sender, receiver, assets, shares);
    }
}

