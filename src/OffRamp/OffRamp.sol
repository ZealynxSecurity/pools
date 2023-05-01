// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IOffRamp} from "src/Types/Interfaces/IOffRamp.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// The Offramp relies on 3 main tokens -
// 1. The IOU token - this is the token that is staked into the Offramp.
// 2. The asset token - this is the token that is distributed to the IOU token holders.
// 3. The liquidStakingToken - this represents an ERC4626 _share_.
//
// We're basically using the IOU token as a way to throttle the conversion from liquidStakngTokens
// into the asset which in most of our cases is wrapped FIL. Since there isn't necesarily
// enough balance to cover all wrapped FIL (or asset) exits we need to use the IOU as an intermediary.
//
// This contract needs to be able to have mint permissions over the IOU token, and it needs to be able
// to burn IOU tokens (when they're exchanged for asset) and liquid staking tokens (when they're exchanged for IOU).

contract OffRamp is IOffRamp, Ownable {

    using FixedPointMathLib for uint256;

    // the conversionWindow protects against flash loan attacks
    uint256 public conversionWindow;
    // the token that gets staked into the Offramp to accrue a balance and eventually exit into the asset.
    // This is the intermediary or synthetic token.
    address public iouToken;
    // the desired token to convert into over time.
    address public asset;
    // This represents an ERC4626 _share_. This is the token that we're "throttling" the exit of.
    address public liquidStakingToken;
    address internal immutable router;
    /**
     * @dev iouTokens start staked,
     * and then move into iouTokensToRealize during the phased distribution,
     * and then move into the assetsToClaim after calling `realize`
     * finally, tokens can be claimed when they are in the assetsToClaim bucket
     */
    mapping(address => uint256) public iouTokensStaked;
    mapping(address => uint256) public iouTokensToRealize;
    mapping(address => uint256) public assetsToClaim;
    // the last point in which the user's bucket was updated
    // the cursor _is_ the value of `totalDividendPoints` at the time of the last update
    mapping(address => uint256) public lastAccountUpdateCursor;

    mapping(address => bool) public userIsKnown;
    mapping(uint256 => address) public userList;
    uint256 public nextUser;

    uint256 public totalIOUStaked;
    uint256 public liquidAssets;
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
        address _asset,
        address _liquidStakingToken,
        address _owner,
        uint256 _poolID
    ) Ownable(_owner){
        router = _router;
        iouToken = _iouToken;
        asset = _asset;
        poolID = _poolID;
        liquidStakingToken = _liquidStakingToken;
        conversionWindow = 50;
    }

    /// @notice this function is called by the InfinityPool to determin how many assets should be sent to the ramp
    function totalExitDemand() external view returns (uint256) {
      return totalIOUStaked;
    }

    /// @notice maxWithdraw returns the maximum amount of assets that can be withdrawn from the ramp
    function maxWithdraw(address account) external view returns (uint256) {
        return GetRoute
            .pool(router, poolID)
            .convertToAssets(IPoolToken(liquidStakingToken).balanceOf(account));
    }

    /// @notice maxRedeem returns the maximum amount of assets that can be withdrawn from the ramp
    function maxRedeem(address account) external view returns (uint256) {
        return IPoolToken(liquidStakingToken).balanceOf(account);
    }

    /// @notice previewWithdraw returns the amount of assets that can be withdrawn from the ramp
    function previewWithdraw(uint256 assets) external view returns (uint256) {
        uint256 supply = IPoolToken(liquidStakingToken).totalSupply(); // Saves an extra SLOAD if totalSupply is non-zero.
        uint256 totalAssets = GetRoute
            .pool(router, poolID)
            .totalAssets();
        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets);
    }

    /// @notice previewRedeem returns the amount of assets that can be withdrawn from the ramp
    function previewRedeem(uint256 shares) external view returns (uint256) {
        return GetRoute
            .pool(router, poolID)
            .convertToAssets(shares);
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
        uint256 _canDistribute = liquidAssets;

        if(_toDistribute > 0){
            // distribute as many tokens as we have liquid (and not accounted for)
            liquidAssets = _toDistribute < _canDistribute
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
        require(assetsToClaim[sender] > 0);
        uint256 value = assetsToClaim[sender];
        assetsToClaim[sender] = 0;
        IERC20(asset).transfer(sender, value);
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
        IPoolToken(iouToken).transfer(sender, amount);
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
        IPoolToken(iouToken).transferFrom(sender, address(this), amount);
        totalIOUStaked = totalIOUStaked + (amount);
        iouTokensStaked[sender] = iouTokensStaked[sender] + (amount);
    }

    ///@dev Deposits ious into the transmuter
    ///
    ///@param amount the amount of ious to stake
    function stakeOnBehalf(uint256 amount, address recipient)
        internal
        runPhasedDistribution()
        updateAccount(msg.sender)
        checkIfNewUser()
    {
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
        assetsToClaim[sender] = assetsToClaim[sender] + (iousToRealize);
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
        assetsToClaim[victim] = assetsToClaim[victim] + (iousToRealize);

        // force payout of realised tokens of the victim address
        if (assetsToClaim[victim] > 0) {
            uint256 value = assetsToClaim[victim];
            assetsToClaim[victim] = 0;
            IERC20(asset).transfer(victim, value);
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
        IERC20(asset).transferFrom(origin, address(this), amount);
        liquidAssets = liquidAssets + (amount);
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
            liquidAssets = liquidAssets + (amount);
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
        claimableIOUs = assetsToClaim[user];
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

    /// @dev Gets info on the liquidAssets
    ///
    /// This function is used to query the contract to get the
    /// latest state of the liquidAssets
    ///
    /// @return _toDistribute the amount ready to be distributed
    /// @return _deltaBlocks the amount of time since the last phased distribution
    /// @return _canDistribute the amount in the liquidAssets
    function bufferInfo() public view returns (
        uint256 _toDistribute,
        uint256 _deltaBlocks,
        uint256 _canDistribute
    ) {
        _deltaBlocks = block.number - (lastDepositBlock);
        _canDistribute = liquidAssets;
        _toDistribute = _getToDistribute();
    }

    function _getToDistribute() internal view returns (uint256 _toDistribute){
        uint256 deltaBlocks = block.number - lastDepositBlock;
        if (deltaBlocks >= conversionWindow) {
            return liquidAssets;
        } else if(liquidAssets * deltaBlocks > conversionWindow) {
            return (liquidAssets * deltaBlocks) / conversionWindow;
        }
        return 0;
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
        address owner,
        uint256 totalAssets
    ) public  returns (uint256 assets) {
        require((assets = previewRedeem(shares, totalAssets)) != 0, "ZERO_ASSETS");
        IPoolToken(liquidStakingToken).burn(owner, shares);
        IPoolToken(iouToken).mint(address(this), assets);
        stakeOnBehalf(assets, receiver);
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
        address owner,
        uint256 totalAssets
    ) public returns (uint256 shares) {
        shares = previewWithdraw(assets, totalAssets);
        IPoolToken(liquidStakingToken).burn(owner, shares);
        IPoolToken(iouToken).mint(address(this), assets);
        stakeOnBehalf(assets, receiver);
    }

    /**
     * @dev Previews the withdraw
     * @param assets The amount of assets to withdraw
     * @return shares - The amount of shares to be converted from assets
     */
    function previewWithdraw(uint256 assets, uint256 totalAssets) public view returns (uint256) {
        uint256 supply = IPoolToken(liquidStakingToken).totalSupply();
        return supply == 0 ? assets : assets * supply / totalAssets;
    }

    /**
     * @dev Previews an amount of assets to redeem for a given number of `shares`
     * @param shares The amount of shares to hypothetically burn
     * @return assets - The amount of assets that would be converted from shares
     */
    function previewRedeem(uint256 shares, uint256 totalAssets) public view returns (uint256) {
        uint256 supply = IPoolToken(liquidStakingToken).totalSupply();
        return supply == 0 ? shares : shares * totalAssets / supply;
    }
}
