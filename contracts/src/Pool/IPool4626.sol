// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import "src/LoanAgent/LoanAgent.sol";

struct Loan {
    // the epoch in which the borrow function was called
    uint256 startEpoch;
    // set at time of borrow / repay / refinance
    uint256 pmtPerEpoch;
    // the total amount borrowed by the loan agent
    uint256 principal;
    // the total cost of the loan
    uint256 interest;
    // the total amount paid off the loan
    uint256 totalPaid;

    // @VIRTUALS:
    // totalLoanValue => principal + interest
    // loanBalance => what you owe or how much you've overpaid
}

/// @title ERC4626 interface
/// See: https://eips.ethereum.org/EIPS/eip-4626
abstract contract IPool4626 is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public treasury;

    uint256 public id;
    uint256 public interestRate;
    uint256 public loanPeriods = 1555200;

    uint256 public fee = 0.025e18; // 2.5%
    uint256 public feesCollected = 0;
    uint256 public feeFlushAmt = 1e18;

    // the borrower must make a payment every 86400 epochs, minimum
    uint256 public gracePeriod = 86400;
    uint256 public penaltyFee = 0.05e18; // 5%

    mapping(address => Loan) private _loans;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Borrow(
        address indexed caller,
        address indexed loanAgent,
        uint256 loanAmount,
        uint256 loanInterest,
        uint256 totalLoanAmount,
        uint256 totalLoanInterest
    );

    event Repay(
        address indexed caller,
        address indexed pool,
        address indexed loanAgent,
        uint256 amount
    );

    event Flush(
        address indexed pool,
        address indexed treasury,
        uint256 amount
    );

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _id,
        // interest rate in percentages (e.g. 55 => 5.5% interest)
        uint256 _interestRate,
        address _treasury
    ) ERC4626(_asset, _name, _symbol) {
        id = _id;
        // TODO: https://github.com/glif-confidential/gcred-contracts/issues/20
        interestRate = _interestRate.divWadUp(100e18);
        treasury = _treasury;
    }

    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/19
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function getLoan(address borrower) public view returns (Loan memory loan) {
        return _loans[borrower];
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return fee.mulWadUp(amount);
    }
    /*////////////////////////////////////////////////////////
                      Pool Borrowing Functions
    ////////////////////////////////////////////////////////*/
    function totalLoanValue(Loan memory _loan) public pure returns (uint256) {
        return _loan.principal + _loan.interest - _loan.totalPaid;
    }

    function pmtPerEpoch(Loan memory _loan) public pure returns (uint256) {
        return _loan.pmtPerEpoch;
    }

    function loanBalance(address borrower) public view returns (uint256 bal, uint256 penalty) {
        Loan memory loan = getLoan(borrower);
        if (loan.startEpoch == 0) {
            return (0, 0);
        }
        uint256 currentPeriod = block.number - loan.startEpoch;
        // don't charge for more periods than the total loan duration
        uint256 maxOwed = currentPeriod > loanPeriods
            ? totalLoanValue(loan)
            : (currentPeriod * 1e18).mulWadUp(loan.pmtPerEpoch);

        if (maxOwed <= loan.totalPaid) {
            return (0, 0);
        }

        uint256 maxBalBeforePenalty = (gracePeriod * 1e18).mulWadUp(loan.pmtPerEpoch);
        uint256 totalOwed = (currentPeriod * 1e18).mulWadUp(loan.pmtPerEpoch);

        if (totalOwed <= maxBalBeforePenalty) {
            return (maxOwed, 0);
        }

        return (maxOwed, penaltyFee.mulWadUp((totalOwed - maxBalBeforePenalty) * 1e18));
    }

    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/1
    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/21
    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/16
    function borrow(uint256 amount, address loanAgent) public virtual returns (uint256 interest) {
        // check
        require(amount <= totalAssets(), "Amount to borrow must be less than this pool's liquid totalAssets");
        // require(!LoanAgent(payable(loanAgent)).isLoanAgent(), "Cannot borrow as a non loan-aget actor");
        // require(!LoanAgent(payable(loanAgent)).hasPenalties(), "Cannot borrow from a pool when LoanAgent is in penalty");

        // effect
        uint256 newInterest = amount.mulWadUp(interestRate);
        interest = _loans[loanAgent].interest + newInterest;
        uint256 principal = _loans[loanAgent].principal + amount;
        _loans[loanAgent] = Loan(
            block.number,
            (principal + interest - _loans[loanAgent].totalPaid).divWadUp(loanPeriods * 1e18),
            principal,
            interest,
            _loans[loanAgent].totalPaid
        );
        emit Borrow(msg.sender, loanAgent, amount, newInterest, principal, interest);

        // interact
        asset.safeTransfer(loanAgent, amount);
    }

    function repay(uint256 amount, address loanAgent, address payee) public virtual {
        // effect
        Loan storage loan = _loans[loanAgent];
        loan.totalPaid += amount;
        if (feesCollected + getFee(amount) > feeFlushAmt) {
            flush();
        } else {
            feesCollected += getFee(amount);
        }
        emit Repay(msg.sender, address(this), loanAgent, amount);

        // interact
        asset.safeTransferFrom(payee, address(this), amount);
    }

    function flush() public virtual {
        // effect
        uint256 flushAmount = feesCollected;
        feesCollected = 0;
        emit Flush(address(this), treasury, flushAmount);

        // interact
        asset.transfer(treasury, flushAmount);
    }
}

