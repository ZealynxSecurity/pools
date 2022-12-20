// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {Agent} from "src/Agent/Agent.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {Router} from "src/Router/Router.sol";

import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IRateModule} from "src/Types/Interfaces/IRateModule.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

/// NOTE: this pool uses accrual basis accounting to compute share prices
contract PoolTemplate is IPool, ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    // NEEDED
    address public treasury;
    address public router;
    uint256 public id;
    address public interestModule;
    uint256 public period;
    uint256 public fee = 0.025e18; // 2.5%
    uint256 public feesCollected = 0;
    uint256 public totalBorrowed = 0;
    ERC20 public powerToken;
    //UNSURE
    // the borrower must make a payment every 86400 epochs, minimum
    uint256 public gracePeriod = 86400;
    uint256 public penaltyFee = 0.05e18; // 5%
    mapping(address => Account) public accounts;

    // The only things we need to pull into this contract are the ones unique to _each pool_
    // This is just the approval module, and the treasury address
    // Everything else is accesible through the router (power token for example)
    constructor(
        string memory _name,
        string memory _symbol,
        address _rateModule,
        address _treasury,
        address _asset,
        address _powerToken
        ) ERC4626(ERC20(_asset), _name, _symbol) {
        treasury = _treasury;
        powerToken = ERC20(_powerToken);
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

    function getAsset() public view override returns (IERC20) {
        return IERC20(address(asset));
    }

    // TODO: Is amount bundled into the VC?
    function borrow(uint256 amount, address agent, VerifiableCredential memory vc, uint256 powerTokenAmount) public virtual returns (uint256 interest) {
        // check
        require(amount <= totalAssets(), "Amount to borrow must be less than this pool's liquid totalAssets");
        // Modify to Role Based solution
        // Do we even need to validate that the borrower is an agent? It's that implicit in the VC?
        //require(stats.isAgent(agent), "Only account agents can borrow from pools");
        // TODO: ROLES ADD THE AGENT MANAGER CHECK HERE
        require(agent == msg.sender, "Cannot borrow on behalf of a account agent you do not own");
        safeTransfer(powerToken, agent, powerTokenAmount);
        // effects
        uint256 pmtPerPeriod = IRateModule(interestModule).getRate(vc, powerTokenAmount);
        uint256 currentTotal = accounts[agent].totalBorrowed;
        uint256 _totalBorrowed = currentTotal + amount;
        totalBorrowed += amount;
        uint accountAge = currentTotal == 0 ? block.number : accounts[agent].startEpoch;
        accounts[agent] = Account(
            accountAge,
            pmtPerPeriod,
            _totalBorrowed,
            block.number+period,
            accounts[agent].powerTokensStaked + powerTokenAmount
        );
        // accrual basis accounting
        emit Borrow(msg.sender, agent, amount, pmtPerPeriod, _totalBorrowed);
        // interact
        safeTransfer(asset, msg.sender, amount);
    }

    function makePayment(address agent, VerifiableCredential memory vc) public virtual {
        Account storage account = accounts[agent];
        uint256 payment = account.pmtPerPeriod;
        safeTransfer(asset, agent, payment);
        account.nextDueDate = account.nextDueDate + period;
    }

    function exitPool(uint256 amount, address agent, VerifiableCredential memory vc) public virtual {
        Account storage account = accounts[agent];
        // Pay back the borrowed asset
        safeTransfer(asset, address(this), amount);
        // The power tokens that must be returned to the pool is the same percent as the amount that the agent wishes to exit
        uint256 powerTokenAmount = amount * account.powerTokensStaked / account.totalBorrowed;
        uint256 newPowerTokenAmount = account.powerTokensStaked - powerTokenAmount;
        // Get the new rate from the rate module
        uint256 pmtPerPeriod = IRateModule(interestModule).getRate(vc, account.powerTokensStaked - powerTokenAmount);
        // Update the account information
        accounts[agent] = Account(
            account.startEpoch,
            pmtPerPeriod,
            account.totalBorrowed - amount,
            account.nextDueDate,
            newPowerTokenAmount
        );
        // Return the power tokens to the agent
        safeTransfer(powerToken, agent, powerTokenAmount);
    }

    function flush() public virtual {
        // effect
        uint256 flushAmount = feesCollected;
        feesCollected = 0;
        emit Flush(address(this), treasury, flushAmount);
        // interact
        asset.transfer(treasury, flushAmount);
    }

    function safeTransfer(
        ERC20 token,
        address to,
        uint256 amount
    ) internal {
        bool success;

        assembly {
            // Get a pointer to some free memory.
            let freeMemoryPointer := mload(0x40)
            // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(freeMemoryPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), to) // Append the "to" argument.
            mstore(add(freeMemoryPointer, 36), amount) // Append the "amount" argument.
            success := and(
                // Set success to whether the call reverted, if not we check it either
                // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                // We use 68 because the length of our calldata totals up like so: 4 + 32 * 2.
                // We use 0 and 32 to copy up to 32 bytes of return data into the scratch space.
                // Counterintuitively, this call must be positioned second to the or() call in the
                // surrounding and() call or else returndatasize() will be zero during the computation.
                call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
            )
        }

        require(success, "TRANSFER_FAILED");
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

        safeTransfer(asset, receiver, assets);
    }

    function getAccount(address agent) public view returns (Account memory) {
        return accounts[agent];
    }

}

