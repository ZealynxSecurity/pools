// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {PoolToken} from "./Tokens/PoolToken.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {Agent} from "src/Agent/Agent.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AuthController} from "src/Auth/AuthController.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IBroker} from "src/Types/Interfaces/IBroker.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolTemplate} from "src/Types/Interfaces/IPoolTemplate.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN} from "src/Constants/Routes.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
contract PoolAccounting is IPool, RouterAware {
    using FixedPointMathLib for uint256;
    // NEEDED
    address public treasury; // This is the account we flush too
    IPoolTemplate public template; // This module handles the primary logic for borrowing and payments
    IBroker public broker; // This module handles logic for approving borrow requests and setting rates/account health
    ERC20 public asset; 
    PoolToken public share; 
    uint256 public fee = 0.025e18; // 2.5%
    uint256 public feesCollected = 0;
    uint256 public totalBorrowed = 0;

    // UNSURE
    uint256 public penaltyFee = 0.05e18; // 5%
    mapping(uint256 => Account) public accounts;

    /*//////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////*/

    modifier requiresAuth() {
        AuthController.requiresSubAuth(router, address(this));
        _;
    }

    modifier onlyAgent() {
        AuthController.onlyAgent(router, msg.sender);
        _;
    }

    modifier onlyTemplate() {
        AuthController.onlyPoolTemplate(router, msg.sender);
        _;
    }


    modifier isValidCredential(address agent, SignedCredential memory signedCredential) {
        _isValidCredential(agent, signedCredential);
        _;
    }

    // The only things we need to pull into this contract are the ones unique to _each pool_
    // This is just the approval module, and the treasury address
    // Everything else is accesible through the router (power token for example)
    constructor(
        address _router,
        address _broker,
        address _asset,
        address _share,
        address _template
    ) {
        share = PoolToken(_share);
        asset = ERC20(_asset);
        broker = IBroker(_broker);
        router = _router;
        template = IPoolTemplate(_template);
        asset.approve(_template, type(uint256).max);
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return fee.mulWadUp(amount);
    }

    /*////////////////////////////////////////////////////////
                      Pool Borrowing Functions
    ////////////////////////////////////////////////////////*/
    function getAgentBorrowed(address agent) public view returns (uint256) {
        return accounts[_addressToID(agent)].totalBorrowed;
    }

    function pmtPerPeriod(address agent) public view returns (uint256) {
        return accounts[_addressToID(agent)].pmtPerPeriod;
    }

    function getAgentBorrowed(Account memory account) public view returns (uint256) {
        return account.totalBorrowed;
    }

    function pmtPerPeriod(Account memory account) public view returns (uint256) {
        return account.pmtPerPeriod;
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + totalBorrowed;
    }

    function getAsset() public view override returns (ERC20) {
        return ERC20(address(asset));
    }

    function getAccount(address agent) public view returns (Account memory) {
        return accounts[_addressToID(agent)];
    }

    function getBroker() public view returns (IBroker) {
        return IBroker(broker);
    }

    function getPowerToken() public view returns (IPowerToken) {
        return IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    }

    // Accounting Setters
    function setAccount(Account memory account, address owner) public onlyTemplate {
        accounts[_addressToID(owner)] = account;
    }

    function resetAccount(address owner) public onlyTemplate {
        accounts[_addressToID(owner)] = Account(0,0,0,0,0);
    }

    // NOTE: Making these seperate saves us a step but maybe there's a smarter way to do this; feels wrong idk
    function reduceTotalBorrowed(uint256 amount) public onlyTemplate {
        totalBorrowed -= amount;
    }

    function increaseTotalBorrowed(uint256 amount) public onlyTemplate {
        totalBorrowed += amount;
    }

    function setFee(uint256 _fee) public requiresAuth {
        fee = _fee;
    }

    // NOTE: We probably want a "collect fees" function?

    // Pass Through Functions
    function borrow(
        uint256 amount,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    ) public onlyAgent isValidCredential(msg.sender, sc) returns (uint256) {
        // pull the powerTokens into the pool
        GetRoute.powerToken(router).transferFrom(msg.sender, address(this), powerTokenAmount);

        template.borrow(
            amount,
            sc.vc,
            powerTokenAmount,
            broker,
            accounts[_addressToID(msg.sender)]
        );
        // interact
        SafeTransferLib.safeTransfer(asset, msg.sender, amount);
    }

    // makes payment using power tokens, priced at the average ratio of powerTokenStake : borrowAmount
    function stakeToPay(
        uint256 pmt,
        SignedCredential memory sc,
        uint256 powerTokenAmount
    ) public onlyAgent isValidCredential(msg.sender, sc) {
        // pull the powerTokens into the pool
        GetRoute.powerToken(router).transferFrom(msg.sender, address(this), powerTokenAmount);

        template.stakeToPay(
            pmt,
            sc.vc,
            powerTokenAmount,
            broker,
            accounts[_addressToID(msg.sender)]
        );
        // no funds get transferred to the agent in this case, since they use the borrowed proceeds to make a payment
    }

    function makePayment(address agent, uint256 pmt) public {
        template.makePayment(agent, accounts[_addressToID(agent)], pmt);
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), pmt);
    }

    function exitPool(
        address agent,
        SignedCredential memory sc,
        uint256 amount
    )
        public
        isValidCredential(agent, sc)
        returns (uint256 powerTokensToReturn)
    {
        // Pull back the borrowed asset
        SafeTransferLib.safeTransferFrom(
            asset,
            agent,
            address(this),
            amount
        );
        powerTokensToReturn = template.exitPool(amount, sc.vc, broker, accounts[_addressToID(agent)]);
        // Return the power tokens to the agent
        GetRoute.powerToken(router).transfer(sc.vc.subject, powerTokensToReturn);
    }


    function flush() public virtual {
        // effect
        uint256 flushAmount = feesCollected;
        feesCollected = 0;
        // interact
        asset.transfer(treasury, flushAmount);
    }

    function _isValidCredential(
        address agent,
        SignedCredential memory signedCredential
    ) internal view returns (bool) {
        return GetRoute.agentPolice(router).isValidCredential(agent, signedCredential);
    }

    function _addressToID(address agent) internal view returns (uint256) {
        return IAgent(agent).id();
    }

    /*//////////////////////////////////////////////////////////////
                            4626 FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = template.deposit(assets, receiver, share, asset);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = template.mint(shares, receiver, share, asset);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = template.withdraw(assets, receiver, owner, share, asset);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public virtual returns (uint256 assets) {
        assets = template.redeem(shares, receiver, owner, share, asset);
    }


    /*//////////////////////////////////////////////////////////////
                            4626 LOGIC
    //////////////////////////////////////////////////////////////*/
    // TODO: Move these into a shared library
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = share.totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(share.balanceOf(owner));
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return share.balanceOf(owner);
    }
}

