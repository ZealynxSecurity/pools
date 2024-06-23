// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {PoolToken} from "shim/PoolToken.sol";
import {WFIL} from "shim/WFIL.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {FinMath} from "src/Pool/FinMath.sol";

import {CredParser} from "src/Credentials/CredParser.sol";
import {Router} from "src/Router/Router.sol";
import {Deployer} from "deploy/Deployer.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";

import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";

import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {ROUTE_WFIL_TOKEN} from "src/Constants/Routes.sol";

import {MockMiner} from "test/helpers/MockMiner.sol";
import {EPOCHS_IN_DAY, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {StateSnapshot} from "./Constants.sol";
import "./Constants.sol";

// an interface with common methods for V1 and V2 pools
interface IMiniPool {
    function liquidStakingToken() external view returns (IPoolToken);

    function convertToShares(uint256) external view returns (uint256);

    function convertToAssets(uint256) external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalBorrowed() external view returns (uint256);

    function getAgentBorrowed(uint256) external view returns (uint256);
}

// this basically just stores a mapping of miners to use as IDs
contract MockIDAddrStore {
    mapping(uint64 => address) public ids;
    uint64 public count = 1;

    function addAddr(address addr) external returns (uint64 id) {
        id = count;
        ids[count] = addr;
        count++;
    }
}

contract CoreTestHelper is Test {
    using FixedPointMathLib for uint256;

    // just used for testing
    uint256 public vcIssuerPk = 1;
    address public vcIssuer;

    string constant VERIFIED_NAME = "glif.io";
    string constant VERIFIED_VERSION = "1";

    address public constant ZERO_ADDRESS = address(0);
    address public treasury = makeAddr("TREASURY");
    address public systemAdmin = makeAddr("SYSTEM_ADMIN");

    IWFIL wFIL = IWFIL(address(new WFIL(systemAdmin)));
    address credParser = address(new CredParser());
    MockIDAddrStore public idStore;

    address public router;

    constructor() {
        vcIssuer = vm.addr(vcIssuerPk);

        vm.startPrank(systemAdmin);
        // deploys the router
        router = address(new Router(systemAdmin));
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        vm.stopPrank();

        address mockIDStoreDeployer = makeAddr("MOCK_ID_STORE_DEPLOYER");
        vm.prank(mockIDStoreDeployer);
        idStore = new MockIDAddrStore();
        require(
            address(idStore) == MinerHelper.ID_STORE_ADDR, "ID_STORE_ADDR must be set to the address of the IDAddrStore"
        );
    }

    function issueAddMinerCred(uint256 agent, uint64 miner) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            1000,
            IAgent.addMiner.selector,
            miner,
            // agent data irrelevant for an add miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issueWithdrawCred(uint256 agent, uint256 amount, AgentData memory agentData)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.withdraw.selector,
            // miner data irrelevant for a withdraw cred
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issueRemoveMinerCred(uint256 agent, uint64 miner, AgentData memory agentData)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            IAgent.removeMiner.selector,
            miner,
            // agent data irrelevant for an remove miner cred
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issuePullFundsCred(uint256 agent, uint64 miner, uint256 amount)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.pullFunds.selector,
            miner,
            // agent data irrelevant for an pull funds from miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issuePushFundsCred(uint256 agent, uint64 miner, uint256 amount)
        internal
        returns (SignedCredential memory)
    {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.pushFunds.selector,
            miner,
            // agent data irrelevant for an push funds to miner cred
            bytes("")
        );

        return signCred(vc);
    }

    function issueGenericPayCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);
        return _issueGenericPayCred(agent, amount);
    }

    function _issuePayCred(uint256 agentID, uint256 principal, uint256 collateralValue, uint256 paymentAmount)
        internal
        returns (SignedCredential memory)
    {
        uint256 adjustedRate = _getAdjustedRate();

        AgentData memory agentData = createAgentData(
            collateralValue,
            // good EDR
            adjustedRate.mulWadUp(principal).mulWadUp(EPOCHS_IN_DAY) * 5,
            principal
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agentID,
            block.number,
            block.number + 100,
            paymentAmount,
            IAgent.pay.selector,
            // minerID irrelevant for pay action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function _issueGenericPayCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        return _issuePayCred(agent, amount, amount * 2, amount);
    }

    function issueGenericRecoverCred(uint256 agent, uint256 faultySectors, uint256 liveSectors)
        internal
        returns (SignedCredential memory)
    {
        AgentData memory agentData = AgentData(
            0,
            0,
            0,
            0,
            // perfect gcred
            100,
            0,
            0,
            // faulty sectors
            faultySectors,
            // livesectors
            liveSectors,
            0
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            IAgent.setRecovered.selector,
            // minerID irrelevant for setRecovered action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function issueGenericSetDefaultCred(uint256 agent, uint256 principal) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);

        // create a cred where DTL >100%
        uint256 collateralValue = 0;

        AgentData memory ad = AgentData(
            1e18,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            0,
            0,
            // qaPower hardcoded
            0,
            principal,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            0,
            IAgentPolice.setAgentDefaultDTL.selector,
            // minerID irrelevant for setDefault action
            0,
            abi.encode(ad)
        );

        return signCred(vc);
    }

    function issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        // roll forward so we don't get an identical credential that's already been used
        vm.roll(block.number + 1);
        return _issueGenericBorrowCred(agent, amount);
    }

    // this is a helper function to allow us to issue a borrow cred without rolling forward
    function _issueGenericBorrowCred(uint256 agent, uint256 amount) internal returns (SignedCredential memory) {
        uint256 principal = amount;
        // NOTE: since we don't pull this off the pool it could be out of sync - careful
        uint256 adjustedRate = FixedPointMathLib.divWadDown(15e34, EPOCHS_IN_YEAR * 1e18);

        AgentData memory agentData = createAgentData(
            // collateralValue => 2x the borrowAmount
            amount * 2,
            // good EDR (5x expected payments)
            (adjustedRate * EPOCHS_IN_DAY * principal * 5) / WAD,
            // principal = borrowAmount
            principal
        );

        VerifiableCredential memory vc = VerifiableCredential(
            vcIssuer,
            agent,
            block.number,
            block.number + 100,
            amount,
            IAgent.borrow.selector,
            // minerID irrelevant for borrow action
            0,
            abi.encode(agentData)
        );

        return signCred(vc);
    }

    function createAgentData(uint256 collateralValue, uint256 expectedDailyRewards, uint256 principal)
        internal
        pure
        returns (AgentData memory)
    {
        // lockedFunds = collateralValue * 1.67 (such that CV = 60% of locked funds)
        uint256 lockedFunds = collateralValue * 167 / 100;
        // agent value = lockedFunds * 1.2 (such that locked funds = 83% of locked funds)
        uint256 agentValue = lockedFunds * 120 / 100;
        return AgentData(
            agentValue,
            collateralValue,
            // expectedDailyFaultPenalties
            0,
            expectedDailyRewards,
            // GCRED DEPRECATED
            100,
            // qaPower hardcoded
            10e18,
            principal,
            // faulty sectors
            0,
            // live sectors
            0,
            // Green Score
            0
        );
    }

    function emptyAgentData() internal pure returns (AgentData memory) {
        return AgentData(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    }

    function signCred(VerifiableCredential memory vc) public returns (SignedCredential memory) {
        bytes32 digest = GetRoute.vcVerifier(router).digest(vc);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vcIssuerPk, digest);
        return SignedCredential(vc, v, r, s);
    }

    function assertPegInTact() internal {
        IMiniPool pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));
        uint256 FILtoIFIL = pool.convertToShares(WAD);
        uint256 IFILtoFIL = pool.convertToAssets(WAD);
        assertEq(FILtoIFIL, IFILtoFIL, "Peg should be 1:1");
        assertEq(FILtoIFIL, WAD, "Peg should be 1:1");
        assertEq(IFILtoFIL, WAD, "Peg should be 1:1");
    }

    function _snapshot(address agent) internal view returns (StateSnapshot memory snapshot) {
        Account memory account = AccountHelpers.getAccount(router, agent, 0);
        snapshot.agentBalanceWFIL = wFIL.balanceOf(agent);
        snapshot.poolBalanceWFIL = wFIL.balanceOf(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));
        snapshot.agentBorrowed = account.principal;
        snapshot.accountEpochsPaid = account.epochsPaid;
    }

    function _getAdjustedRate() internal pure returns (uint256) {
        return FixedPointMathLib.divWadDown(15e34, EPOCHS_IN_YEAR * 1e18);
    }

    function testInvariants(string memory label) internal {
        _invIFILWorthAssetsOfPool(label);
    }

    function _invIFILWorthAssetsOfPool(string memory label) internal {
        uint256 MAX_PRECISION_DELTA = 1;
        // this invariant knows that iFIL should represent the total value of the pool, which is composed of:
        // 1. all funds given to miners + agents
        // 2. balance of wfil held by the pool
        // 3. minus any fees held temporarily by the pool
        uint256 agentCount = GetRoute.agentFactory(router).agentCount();
        IMiniPool pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));

        uint256 totalDebtFromAccounts = 0;
        uint256 totalInterestFromAccounts = 0;
        uint256 totalBorrowedFromAccounts = 0;

        for (uint256 i = 1; i <= agentCount; i++) {
            Account memory account = AccountHelpers.getAccount(router, i, 0);
            // the invariant breaks when an account is in default, we no longer expect to get that amount back
            if (!account.defaulted) {
                totalBorrowedFromAccounts += pool.getAgentBorrowed(i);
                totalDebtFromAccounts += _agentDebt(i, _getAdjustedRate());
                totalInterestFromAccounts += _agentInterest(i, _getAdjustedRate());
            }
        }

        assertEq(
            pool.totalBorrowed(),
            totalBorrowedFromAccounts,
            "total borrowed from accounts should match pool totalBorrowed"
        );

        // here we try to get the total amount of rewards we've accrued
        // but if were in a first generation pool, this call does not exist, so we just move along without it
        try IPool(address(pool)).lpRewards() {
            IPool _pool = IPool(address(pool));
            // now we know we're in a v2 pool
            uint256 paid = _pool.lpRewards().paid;
            // the difference between what our current debt is and what we've borrowed is the total amount we've accrued
            // we add back what had paid in interest to get the total amount of rewards we've accrued
            uint256 accruedRewards = totalDebtFromAccounts - totalBorrowedFromAccounts + paid;

            assertEq(
                accruedRewards,
                totalInterestFromAccounts + paid,
                string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: accrued rewards calculations should match"))
            );

            assertApproxEqAbs(
                accruedRewards,
                _pool.lpRewards().accrued,
                MAX_PRECISION_DELTA,
                string(
                    abi.encodePacked(
                        label,
                        " _invIFILWorthAssetsOfPool: accrued rewards in each account should match total pool accrued rewards"
                    )
                )
            );
            uint256 poolAssets = wFIL.balanceOf(address(pool));

            // if we take the total supply of iFIL and convert it to assets, we should get the total pools assets + lent out funds
            uint256 totalIFILSupply = pool.liquidStakingToken().totalSupply();

            assertApproxEqAbs(
                poolAssets + totalDebtFromAccounts - _pool.treasuryFeesOwed(),
                pool.totalAssets(),
                MAX_PRECISION_DELTA,
                string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: pool total assets invariant wrong"))
            );
            assertApproxEqAbs(
                pool.convertToAssets(totalIFILSupply),
                poolAssets + totalDebtFromAccounts - _pool.treasuryFeesOwed(),
                MAX_PRECISION_DELTA,
                string(
                    abi.encodePacked(label, " _invIFILWorthAssetsOfPool: iFIL convert to total assets invariant wrong")
                )
            );
            assertEq(
                pool.totalBorrowed(),
                totalBorrowedFromAccounts,
                string(abi.encodePacked(label, " _invIFILWorthAssetsOfPool: total borrowed invariant wrong"))
            );
        } catch Error(string memory) {
            // now we know we're in a v1 pool
        }
    }

    function _agentDebt(IAgent agent, uint256 perEpochRate) internal view returns (uint256) {
        return _agentDebt(agent.id(), perEpochRate);
    }

    function _agentDebt(uint256 agentID, uint256 perEpochRate) internal view returns (uint256) {
        return FinMath.computeDebt(AccountHelpers.getAccount(router, agentID, 0), perEpochRate);
    }

    function _agentInterest(IAgent agent, uint256 perEpochRate) internal view returns (uint256) {
        return _agentInterest(agent.id(), perEpochRate);
    }

    function _agentInterest(uint256 agentID, uint256 perEpochRate) internal view returns (uint256) {
        (uint256 interestOwed,) = FinMath.interestOwed(AccountHelpers.getAccount(router, agentID, 0), perEpochRate);
        return interestOwed;
    }

    uint256[10] levels = [
        // in prod, we don't set the 0th level to be max_uint, but we do this in testing to by default allow agents to borrow the max amount
        MAX_UINT256,
        MAX_UINT256 / 9,
        MAX_UINT256 / 8,
        MAX_UINT256 / 7,
        MAX_UINT256 / 6,
        MAX_UINT256 / 5,
        MAX_UINT256 / 4,
        MAX_UINT256 / 3,
        MAX_UINT256 / 2,
        MAX_UINT256
    ];
}
