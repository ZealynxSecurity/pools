// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {AuthController} from "src/Auth/AuthController.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Roles} from "src/Constants/Roles.sol";
import {ROUTE_AGENT_FACTORY, ROUTE_POWER_TOKEN} from "src/Constants/Routes.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
contract PoolTemplate is IPool, RouterAware, ERC4626 {
    using FixedPointMathLib for uint256;
    // NEEDED
    address public treasury;
    uint256 public id;
    address public rateModule;
    // the borrower must make a payment every 86400 epochs, minimum
    uint256 public period = 86400;
    uint256 public fee = 0.025e18; // 2.5%
    uint256 public feesCollected = 0;
    uint256 public totalBorrowed = 0;

    // UNSURE
    uint256 public penaltyFee = 0.05e18; // 5%
    mapping(address => Account) public accounts;

    /*//////////////////////////////////////
                MODIFIERS
    //////////////////////////////////////*/

    modifier requiresAuth() {
        require(AuthController.canCallSubAuthority(router, address(this)), "Pool: Not authorized");
        _;
    }

    modifier onlyAgent(address caller) {
        require(
            IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY)).isAgent(caller),
            "Pool: Caller is not an agent"
        );
        _;
    }


    // The only things we need to pull into this contract are the ones unique to _each pool_
    // This is just the approval module, and the treasury address
    // Everything else is accesible through the router (power token for example)
    constructor(
        string memory _name,
        string memory _symbol,
        address _router,
        address _rateModule,
        address _asset
    ) ERC4626(ERC20(_asset), _name, _symbol) {
        rateModule = _rateModule;
        router = _router;
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return fee.mulWadUp(amount);
    }

    /*////////////////////////////////////////////////////////
                      Pool Borrowing Functions
    ////////////////////////////////////////////////////////*/

    function getAgentBorrowed(address agent) public view returns (uint256) {
        return accounts[agent].totalBorrowed;
    }

    function pmtPerPeriod(address agent) public view returns (uint256) {
        return accounts[agent].pmtPerPeriod;
    }

    function getAgentBorrowed(Account memory account) public view returns (uint256) {
        return account.totalBorrowed;
    }

    function pmtPerPeriod(Account memory account) public view returns (uint256) {
        return account.pmtPerPeriod;
    }

    function nextDueDate(Account memory account) public view returns (uint256) {
        return account.nextDueDate;
    }

    function nextDueDate(address agent) public view returns (uint256) {
        return accounts[agent].nextDueDate;
    }

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this)) + totalBorrowed;
    }

    function getAsset() public view override returns (ERC20) {
        return ERC20(address(asset));
    }

    function enableOperator(address newOperator) external requiresAuth {
        IMultiRolesAuthority(
            address(AuthController.getSubAuthority(router, address(this)))
        ).setUserRole(newOperator, uint8(Roles.ROLE_POOL_OPERATOR), true);
    }

    function disableOperator(address operator) external requiresAuth {
        IMultiRolesAuthority(
            address(AuthController.getSubAuthority(router, address(this)))
        ).setUserRole(operator, uint8(Roles.ROLE_POOL_OPERATOR), false);
    }

    function enableOwner(address newOwner) external requiresAuth {
        IMultiRolesAuthority(
            address(AuthController.getSubAuthority(router, address(this)))
        ).setUserRole(newOwner, uint8(Roles.ROLE_POOL_OWNER), true);
    }

    function disableOwner(address owner) external requiresAuth {
        IMultiRolesAuthority(
            address(AuthController.getSubAuthority(router, address(this)))
        ).setUserRole(owner, uint8(Roles.ROLE_POOL_OWNER), false);
    }

    function borrow(
        uint256 amount,
        VerifiableCredential memory vc,
        uint256 powerTokenAmount
    ) public onlyAgent(msg.sender) returns (uint256) {
        // check
        require(msg.sender == vc.subject, "VC Issued to wrong agent");
        require(amount <= totalAssets(), "Amount to borrow must be less than this pool's liquid totalAssets");
        // TODO: require(amount <= vc.amount) https://github.com/glif-confidential/pools/issues/120

        // pull the powerTokens into the pool
        getPowerToken().transferFrom(msg.sender, address(this), powerTokenAmount);

        // effects
        uint256 _pmtPerPeriod = IRateModule(rateModule).getRate(vc, powerTokenAmount);
        uint256 currentTotal = accounts[msg.sender].totalBorrowed;
        uint256 _totalBorrowed = currentTotal + amount;
        totalBorrowed += amount;
        uint accountAge = currentTotal == 0 ? block.number : accounts[msg.sender].startEpoch;
        accounts[msg.sender] = Account(
            accountAge,
            _pmtPerPeriod,
            accounts[msg.sender].powerTokensStaked + powerTokenAmount,
            _totalBorrowed,
            block.number+period
        );

        // accrual basis accounting
        emit Borrow(msg.sender, amount, _pmtPerPeriod, _totalBorrowed);

        // interact
        SafeTransferLib.safeTransfer(asset, msg.sender, amount);

        return _pmtPerPeriod;
    }

    function makePayment(
        address agent,
        VerifiableCredential memory vc
    ) public onlyAgent(msg.sender) {
        Account storage account = accounts[msg.sender];
        uint256 payment = account.pmtPerPeriod;
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), payment);
        account.nextDueDate = account.nextDueDate + period;
    }

    function exitPool(
        uint256 amount,
        VerifiableCredential memory vc
    ) public onlyAgent(msg.sender) {
        Account storage account = accounts[msg.sender];
        // Pull back the borrowed asset
        SafeTransferLib.safeTransferFrom(asset, msg.sender, address(this), amount);
        // The power tokens that must be returned to the pool is the same percent as the amount that the agent wishes to exit
        uint256 powerTokenAmount = amount * account.powerTokensStaked / account.totalBorrowed;
        uint256 newPowerTokenAmount = account.powerTokensStaked - powerTokenAmount;
        // Get the new rate from the rate module
        uint256 _pmtPerPeriod = IRateModule(rateModule).getRate(vc, account.powerTokensStaked - powerTokenAmount);

        totalBorrowed -= amount;
        if (totalBorrowed == 0) {
            // if account is paid off, reset account info
            accounts[msg.sender] = Account(
                0,
                0,
                0,
                0,
                0
            );

        } else {
            // else handle a partial payment
            accounts[msg.sender] = Account(
                account.startEpoch,
                _pmtPerPeriod,
                newPowerTokenAmount,
                account.totalBorrowed - amount,
                account.nextDueDate
            );

        }
        // Return the power tokens to the agent
        getPowerToken().transfer(msg.sender, powerTokenAmount);
    }

    function flush() public virtual {
        // effect
        uint256 flushAmount = feesCollected;
        feesCollected = 0;
        emit Flush(address(this), treasury, flushAmount);
        // interact
        asset.transfer(treasury, flushAmount);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override virtual returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        if(assets > asset.balanceOf(address(this))) {
            assets = asset.balanceOf(address(this));
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransfer(asset, receiver, assets);
    }

    function getAccount(address agent) public view returns (Account memory) {
        return accounts[agent];
    }

    function getPowerToken() internal view returns (IPowerToken) {
        return IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    }

}

