// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {RouterAware} from "src/Router/RouterAware.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Ownable} from "src/Auth/Ownable.sol";

contract OffRamp is IOffRamp, RouterAware, Ownable {
    using SafeTransferLib for ERC20;

    // the conversionWindow protects against flash loan attacks
    uint256 public conversionWindow;
    // the token that gets staked into the Offramp to accrue a balance
    address public iouToken;
    // the desired token to convert into
    address public exitToken;

    /**
     * @dev iouTokens start staked,
     * and then move into iouTokensToRealize during the phased distribution,
     * and then move into the exitTokensToClaim after calling `realize`
     * finally, tokens can be claimed when they are in the exitTokensToClaim bucket
     */
    mapping(address => uint256) public iouTokensStaked;
    mapping(address => uint256) public iouTokensToRealize;
    mapping(address => uint256) public exitTokensToClaim;
    // the last point in which the user's bucket was updated
    // the cursor _is_ the value of `totalDividendPoints` at the time of the last update
    mapping(address => uint256) public lastAccountUpdateCursor;

    mapping(address => bool) public userIsKnown;
    mapping(uint256 => address) public userList;
    uint256 public nextUser;

    uint256 public totalIOUStaked;
    uint256 public liquidExitTokens;
    uint256 public lastDepositBlock;

    ///@dev values needed to calculate the distribution of base asset in proportion for ious staked
    uint256 public pointMultiplier = 10e18;

    uint256 public totalDividendPoints;
    uint256 public unclaimedDividends;

    /// @dev the ID of the pool this offramp is associated with
    uint256 public poolID;

    constructor(
        address _router,
        address _iouToken,
        address _exitToken,
        address _owner,
        uint256 _poolID
    ) Ownable(_owner){
        router = _router;
        iouToken = _iouToken;
        exitToken = _exitToken;
        poolID = _poolID;
        conversionWindow = 50;
    }

    ///@return displays the user's share of the pooled ious.
    function dividendsOwing(address account) public view returns (uint256) {
        // remember that `lastAccountUpdateCursor` was the totalDividendPoints when the account was updated last
        // leaving the newDividendPoints owed as the difference between whats accrued, and what's already been realized
        uint256 newDividendPoints = totalDividendPoints - (lastAccountUpdateCursor[account]);
        return (iouTokensStaked[account] * newDividendPoints) / (pointMultiplier);
    }

    ///@dev modifier to fill the bucket and keep bookkeeping correct incase of increase/decrease in shares
    modifier updateAccount(address account) {
        uint256 owing = dividendsOwing(account);
        if (owing > 0) {
            unclaimedDividends = unclaimedDividends - (owing);
            iouTokensToRealize[account] = iouTokensToRealize[account] + (owing);
        }
        lastAccountUpdateCursor[account] = totalDividendPoints;
        _;
    }
    ///@dev modifier add users to userlist. Users are indexed in order to keep track of when a bond has been filled
    modifier checkIfNewUser() {
        if (!userIsKnown[msg.sender]) {
            userList[nextUser] = msg.sender;
            userIsKnown[msg.sender] = true;
            nextUser++;
        }
        _;
    }

    ///@dev run the phased distribution of the buffered funds
    modifier runPhasedDistribution() {
        uint256 _currentBlock = block.number;
        uint256 _toDistribute = _getToDistribute();
        uint256 _canDistribute = liquidExitTokens;

        if(_toDistribute > 0){
            // distribute as many tokens as we have liquid (and not accounted for)
            liquidExitTokens = _toDistribute < _canDistribute
                ? _canDistribute - (_toDistribute)
                : 0;
            // increase the allocation
            increaseAllocations(_toDistribute);
        }

        // current timeframe is now the last
        lastDepositBlock = _currentBlock;
        _;
    }

    ///@dev set the TRANSMUTATION_PERIOD variable
    ///
    /// sets the length (in blocks) of one full distribution phase
    function setConversionWindow(uint256 newTransmutationPeriod) public onlyOwner {
        conversionWindow = newTransmutationPeriod;
        emit TransmuterPeriodUpdated(conversionWindow);
    }

    ///@dev claims the base token after it has been transmuted
    ///
    ///This function reverts if there is no realisedToken balance
    function claim() public {
        address sender = msg.sender;
        require(exitTokensToClaim[sender] > 0);
        uint256 value = exitTokensToClaim[sender];
        exitTokensToClaim[sender] = 0;
        ERC20(exitToken).safeTransfer(sender, value);
    }

    ///@dev Withdraws staked ious from the transmuter
    ///
    /// This function reverts if you try to draw more tokens than you deposited
    ///
    ///@param amount the amount of ious to unstake
    function unstake(uint256 amount) public updateAccount(msg.sender) {
        // by calling this function before transmuting you forfeit your gained allocation
        address sender = msg.sender;
        require(iouTokensStaked[sender] >= amount,"Transmuter: unstake amount exceeds deposited amount");
        iouTokensStaked[sender] = iouTokensStaked[sender] - (amount);
        totalIOUStaked = totalIOUStaked - (amount);
        ERC20(iouToken).safeTransfer(sender, amount);
    }
    ///@dev Deposits ious into the transmuter
    ///
    ///@param amount the amount of ious to stake
    function stake(uint256 amount)
        public
        runPhasedDistribution()
        updateAccount(msg.sender)
        checkIfNewUser()
    {
        // requires approval of iouToken first
        address sender = msg.sender;
        //require tokens transferred in;
        ERC20(iouToken).safeTransferFrom(sender, address(this), amount);
        totalIOUStaked = totalIOUStaked + (amount);
        iouTokensStaked[sender] = iouTokensStaked[sender] + (amount);
    }

    ///@dev Deposits ious into the transmuter
    ///
    ///@param amount the amount of ious to stake
    function stakeOnBehalf(uint256 amount, address recipient)
        public
        runPhasedDistribution()
        updateAccount(msg.sender)
        checkIfNewUser()
    {
        // requires approval of iouToken first
        address sender = msg.sender;
        //require tokens transferred in;
        ERC20(iouToken).safeTransferFrom(sender, address(this), amount);
        totalIOUStaked = totalIOUStaked + (amount);
        iouTokensStaked[recipient] = iouTokensStaked[recipient] + (amount);
    }

    /// @dev Moves the realized staked iouTokens into the claimable bucket
    function realize() public runPhasedDistribution() updateAccount(msg.sender) {
        address sender = msg.sender;
        uint256 iousToRealize = iouTokensToRealize[sender];
        uint256 diff;

        require(iousToRealize > 0, "need to have tokens to realize");

        iouTokensToRealize[sender] = 0;

        // check bucket overflow
        if (iousToRealize > iouTokensStaked[sender]) {
            diff = iousToRealize - (iouTokensStaked[sender]);

            // remove overflow
            iousToRealize = iouTokensStaked[sender];
        }

        // decrease ious
        iouTokensStaked[sender] = iouTokensStaked[sender] - (iousToRealize);

        // burn ious
        IPoolToken(iouToken).burn(address(this), iousToRealize);

        // adjust total
        totalIOUStaked = totalIOUStaked - (iousToRealize);

        // reallocate overflow
        increaseAllocations(diff);

        // add payout
        exitTokensToClaim[sender] = exitTokensToClaim[sender] + (iousToRealize);
    }

    /// @dev Executes realize() on another account that has had more base tokens allocated to it than ious staked.
    ///
    /// The caller of this function will have the surlus base tokens credited to their iouTokensToRealize balance, rewarding them for performing this action
    ///
    /// This function reverts if the address to realize is not over-filled.
    ///
    /// @param victim address of the account you will force realize.
    function forceRealize(address victim)
        public
        runPhasedDistribution()
        updateAccount(msg.sender)
        updateAccount(victim)
    {
        //load into memory
        address sender = msg.sender;
        uint256 iousToRealize = iouTokensToRealize[victim];
        // check restrictions
        require(
            iousToRealize > iouTokensStaked[victim],
            "Transmuter: !overflow"
        );

        // empty bucket
        iouTokensToRealize[victim] = 0;

        // calculaate diffrence
        uint256 diff = iousToRealize - (iouTokensStaked[victim]);

        // remove overflow
        iousToRealize = iouTokensStaked[victim];

        // decrease ious
        iouTokensStaked[victim] = 0;

        // burn ious
        IPoolToken(iouToken).burn(address(this), iousToRealize);

        // adjust total
        totalIOUStaked = totalIOUStaked - (iousToRealize);

        // reallocate overflow
        iouTokensToRealize[sender] = iouTokensToRealize[sender] + (diff);

        // add payout
        exitTokensToClaim[victim] = exitTokensToClaim[victim] + (iousToRealize);

        // force payout of realised tokens of the victim address
        if (exitTokensToClaim[victim] > 0) {
            uint256 value = exitTokensToClaim[victim];
            exitTokensToClaim[victim] = 0;
            ERC20(exitToken).safeTransfer(victim, value);
        }
    }

    /// @dev Realizes and unstakes all ious
    ///
    /// This function combines the realize and unstake functions for ease of use
    function exit() public {
        realize();
        uint256 toWithdraw = iouTokensStaked[msg.sender];
        unstake(toWithdraw);
    }

    /// @dev Realizes and claims all converted base tokens.
    ///
    /// This function combines the realize and claim functions while leaving your remaining ious staked.
    function realizeAndClaim() public {
        realize();
        claim();
    }

    /// @dev Realizes, claims base tokens, and withdraws ious.
    ///
    /// This function helps users to exit the offramp contract completely after converting their ious to the base pair.
    function realizeClaimAndWithdraw() public {
        realize();
        claim();
        uint256 toWithdraw = iouTokensStaked[msg.sender];
        unstake(toWithdraw);
    }

    /// @dev Distributes the base token proportionally to all iouToken stakers.
    ///
    /// This function is meant to be called by the Alchemist contract for when it is sending yield to the offramp.
    /// Anyone can call this and add funds, idk why they would do that though...
    ///
    /// @param origin the account that is sending the tokens to be distributed.
    /// @param amount the amount of base tokens to be distributed to the offramp.
    function distribute(
        address origin,
        uint256 amount
    ) public runPhasedDistribution() {
        ERC20(exitToken).safeTransferFrom(origin, address(this), amount);
        liquidExitTokens = liquidExitTokens + (amount);
    }

    /// @dev Allocates the incoming yield proportionally to all iouToken stakers.
    ///
    /// @param amount the amount of base tokens to be distributed in the transmuter.
    function increaseAllocations(uint256 amount) internal {
        if(totalIOUStaked > 0 && amount > 0) {
            totalDividendPoints = totalDividendPoints + (
                amount * (pointMultiplier) / (totalIOUStaked)
            );
            unclaimedDividends = unclaimedDividends + (amount);
        } else {
            liquidExitTokens = liquidExitTokens + (amount);
        }
    }

    /// @dev Gets the status of a user's staking position.
    ///
    /// The total amount allocated to a user is the sum of pendingdivs and inbucket.
    ///
    /// @param user the address of the user you wish to query.
    ///
    /// returns user status

    function userInfo(address user)
        public
        view
        returns (
            uint256 stakedIOUs,
            uint256 pendingDivs,
            uint256 realizeableIOUs,
            uint256 claimableIOUs
        )
    {
        stakedIOUs = iouTokensStaked[user];
        uint256 _toDistribute = _getToDistribute();
        pendingDivs = totalIOUStaked  > 0 ? (_toDistribute * iouTokensStaked[user]) / (totalIOUStaked) : 0;
        realizeableIOUs = iouTokensToRealize[user] + (dividendsOwing(user));
        claimableIOUs = exitTokensToClaim[user];
    }

    /// @dev Gets the status of multiple users in one call
    ///
    /// This function is used to query the contract to check for
    /// accounts that have overfilled positions in order to check
    /// who can be force transmuted.
    ///
    /// @param from the first index of the userList
    /// @param to the last index of the userList
    ///
    /// returns the userList with their staking status in paginated form.
    function getMultipleUserInfo(uint256 from, uint256 to)
        public
        view
        returns (address[] memory theUserList, uint256[] memory theUserData)
    {
        uint256 i = from;
        uint256 delta = to - from;
        address[] memory _theUserList = new address[](delta); //user
        uint256[] memory _theUserData = new uint256[](delta * 2); //deposited-bucket
        uint256 y = 0;
        uint256 _toDistribute = _getToDistribute();
        // TODO: Make this more efficient
        for (uint256 x = 0; x < delta; x += 1) {
            _theUserList[x] = userList[i];
            _theUserData[y] = iouTokensStaked[userList[i]];
            _theUserData[y + 1] = (dividendsOwing(userList[i]) + (iouTokensToRealize[userList[i]]) + (_toDistribute * (iouTokensStaked[userList[i]])) / (totalIOUStaked));
            y += 2;
            i += 1;
        }
        return (_theUserList, _theUserData);
    }

    /// @dev Gets info on the liquidExitTokens
    ///
    /// This function is used to query the contract to get the
    /// latest state of the liquidExitTokens
    ///
    /// @return _toDistribute the amount ready to be distributed
    /// @return _deltaBlocks the amount of time since the last phased distribution
    /// @return _canDistribute the amount in the liquidExitTokens
    function bufferInfo() public view returns (
        uint256 _toDistribute,
        uint256 _deltaBlocks,
        uint256 _canDistribute
    ) {
        _deltaBlocks = block.number - (lastDepositBlock);
        _canDistribute = liquidExitTokens;
        _toDistribute = _getToDistribute();
    }

    function _getToDistribute() internal view returns (uint256 _toDistribute){
        uint256 deltaBlocks = block.number - lastDepositBlock;
        if (deltaBlocks >= conversionWindow) {
            return liquidExitTokens;
        } else if(liquidExitTokens * deltaBlocks > conversionWindow) {
            return (liquidExitTokens * deltaBlocks) / conversionWindow;
        }
        return 0;
    }

}
