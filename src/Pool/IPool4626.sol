// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

struct Loan {
    // the epoch in which the borrow function was called
    uint256 startEpoch;
    // the loan duration in epochs
    uint256 periods;
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
abstract contract IPOOL4626 is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 public id;
    uint256 public interestRate;
    uint256 public loanPeriods = 1555200;

    mapping(address => Loan) private _loans;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint256 _id,
        // interest rate in percentages (e.g. 55 => 5.5% interest)
        uint256 _interestRate
    ) ERC4626(_asset, _name, _symbol) {
        id = _id;
        // TODO: https://github.com/glif-confidential/gcred-contracts/issues/20
        interestRate = _interestRate.divWadUp(100e18);
    }

    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/19
    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function getLoan(address borrower) public view returns (Loan memory loan) {
        return _loans[borrower];
    }
    /*////////////////////////////////////////////////////////
                      Pool Borrowing Functions
    ////////////////////////////////////////////////////////*/
    function totalLoanValue(Loan memory _loan) public pure returns (uint256) {
        return _loan.principal + _loan.interest;
    }

    function pmtPerEpoch(Loan memory _loan) public pure returns (uint256) {
        return totalLoanValue(_loan).divWadUp(_loan.periods * 1e18);
    }

    function loanBalance(Loan memory _loan) public view returns (uint256 amount) {
        uint256 currentPeriod = block.number - _loan.startEpoch;
        uint256 amountShouldHavePaid = (currentPeriod * 1e18).mulWadUp(pmtPerEpoch(_loan));
        return amountShouldHavePaid - _loan.totalPaid;
    }

    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/1
    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/21
    // TODO: https://github.com/glif-confidential/gcred-contracts/issues/16
    function borrow(uint256 amount, address loanAgent) public virtual {
        require(amount <= totalAssets(), "Amount to borrow must be less than this pool's liquid totalAssets");
        uint256 interest = amount.mulWadUp(interestRate);
        _loans[loanAgent] = Loan(block.number, loanPeriods, amount, interest, 0);
        asset.safeTransfer(loanAgent, amount);
    }

    function repay(uint256 amount, address loanAgent, address payee) public virtual {
        asset.safeTransferFrom(payee, address(this), amount);
        Loan storage loan = _loans[loanAgent];
        loan.totalPaid += amount;
    }
}

