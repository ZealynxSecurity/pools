// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {CoreTestHelper} from "test/helpers/CoreTestHelper.sol";
import {MockMiner} from "test/helpers/MockMiner.sol";

import {PoolToken} from "shim/PoolToken.sol";
import {WFIL} from "shim/WFIL.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Deployer} from "deploy/Deployer.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {AccountHelpers} from "src/Pool/Account.sol";
import {Agent} from "src/Agent/Agent.sol";
import {AgentFactory} from "src/Agent/AgentFactory.sol";
import {AgentDeployer} from "src/Agent/AgentDeployer.sol";
import {AgentPoliceV2} from "src/Agent/AgentPoliceV2.sol";
import {MinerRegistry} from "src/Agent/MinerRegistry.sol";
import {AuthController} from "src/Auth/AuthController.sol";
import {Router} from "src/Router/Router.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {MockIDAddrStore} from "test/helpers/MockIDAddrStore.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {Credentials} from "src/Types/Structs/Credentials.sol";
import {ROUTE_INFINITY_POOL} from "src/Constants/Routes.sol";
import {EPOCHS_IN_WEEK, EPOCHS_IN_DAY, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import {errorSelector} from "./Utils.sol";

import "src/Constants/Routes.sol";
import "test/helpers/Constants.sol";

// an interface with common methods for V1 and V2 pools
interface IMiniPool {
    function convertToShares(uint256) external view returns (uint256);

    function convertToAssets(uint256) external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalBorrowed() external view returns (uint256);

    function getAgentBorrowed(uint256) external view returns (uint256);
}

contract AgentTestHelper is CoreTestHelper {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    constructor() {}

    function configureAgent(address minerOwner) public returns (IAgent agent, uint64 minerID) {
        uint64 miner = _newMiner(minerOwner);
        // create an agent for miner
        agent = _configureAgent(minerOwner, miner);
        return (agent, miner);
    }

    function _configureAgent(address minerOwner, uint64 miner) internal returns (IAgent agent) {
        IAgentFactory agentFactory = IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY));
        vm.startPrank(minerOwner);
        agent = Agent(payable(agentFactory.create(minerOwner, minerOwner, makeAddr("ADO_REQUEST_KEY"))));
        assertTrue(miner.isOwner(minerOwner), "The mock miner's current owner should be set to the original owner");
        vm.stopPrank();

        _agentClaimOwnership(address(agent), miner, minerOwner);
        return IAgent(address(agent));
    }

    function configureMiner(address _agent, address minerOwner) public returns (uint64 miner) {
        miner = _newMiner(minerOwner);
        _agentClaimOwnership(address(_agent), miner, minerOwner);
    }

    function _newMiner(address minerOwner) internal returns (uint64 id) {
        vm.prank(minerOwner);
        MockMiner miner = new MockMiner(minerOwner);

        id = MockIDAddrStore(MinerHelper.ID_STORE_ADDR).addAddr(address(miner));
        miner.setID(id);
    }

    function _agentClaimOwnership(address _agent, uint64 _miner, address _minerOwner) internal {
        IMinerRegistry registry = IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY));
        IAgent agent = IAgent(_agent);

        vm.startPrank(_minerOwner);
        _miner.changeOwnerAddress(address(_agent));
        vm.stopPrank();

        SignedCredential memory addMinerCred = issueAddMinerCred(agent.id(), _miner);
        // confirm change owner address (agent now owns miner)
        vm.startPrank(_minerOwner);
        agent.addMiner(addMinerCred);
        vm.stopPrank();

        assertTrue(_miner.isOwner(_agent), "The mock miner's owner should change to the agent");
        assertTrue(
            registry.minerRegistered(agent.id(), _miner),
            "After adding the miner the registry should have the miner's address as a registered miner"
        );
    }

    function agentBorrow(IAgent agent, SignedCredential memory sc) internal {
        uint256 poolID = 0;
        IMiniPool pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), poolID)));
        uint256 preTotalBorrowed = pool.totalBorrowed();
        testInvariants("agentBorrow Start");
        vm.startPrank(_agentOwner(agent));
        // Establsh the state before the borrow
        StateSnapshot memory preBorrowState = _snapshot(address(agent), poolID);
        Account memory account = AccountHelpers.getAccount(router, address(agent), poolID);
        uint256 borrowBlock = block.number;
        agent.borrow(poolID, sc);

        vm.stopPrank();
        // Check the state after the borrow
        uint256 currentAgentBal = wFIL.balanceOf(address(agent));
        uint256 currentPoolBal = wFIL.balanceOf(address(GetRoute.pool(GetRoute.poolRegistry(router), poolID)));
        assertEq(currentAgentBal, preBorrowState.agentBalanceWFIL + sc.vc.value, "Agent's balance should increase");
        assertEq(currentPoolBal, preBorrowState.poolBalanceWFIL - sc.vc.value, "Pool's balance should decrease");

        account = AccountHelpers.getAccount(router, address(agent), poolID);

        // first time borrowing, check the startEpoch
        if (preBorrowState.agentBorrowed == 0) {
            assertEq(account.startEpoch, borrowBlock, "Account startEpoch should be correct");
            assertEq(account.epochsPaid, borrowBlock, "Account epochsPaid should be correct");
        }

        if (!account.defaulted) {
            assertEq(
                account.principal, preBorrowState.agentBorrowed + sc.vc.value, "Account principal should be correct"
            );
            assertEq(
                pool.getAgentBorrowed(agent.id()) - preBorrowState.agentBorrowed,
                currentAgentBal - preBorrowState.agentBalanceWFIL,
                "Pool agentBorrowed should increase by the right amount"
            );
            assertEq(
                pool.totalBorrowed(),
                preTotalBorrowed + currentAgentBal - preBorrowState.agentBalanceWFIL,
                "Pool totalBorrowed should be correct"
            );
        }
        testInvariants("agentBorrow End");
    }

    function _agentPay(IAgent agent, SignedCredential memory sc, uint256 perEpochRate)
        internal
        returns (uint256 epochsPaid, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState)
    {
        IMiniPool pool = IMiniPool(address(GetRoute.pool(GetRoute.poolRegistry(router), 0)));

        testInvariants("agentPay Start");
        vm.startPrank(address(agent));
        vm.deal(address(agent), sc.vc.value);
        wFIL.deposit{value: sc.vc.value}();
        wFIL.approve(address(pool), sc.vc.value);
        vm.stopPrank();

        vm.startPrank(_agentOperator(agent));

        uint256 prePayEpochsPaid = AccountHelpers.getAccount(router, address(agent), 0).epochsPaid;

        prePayState = _snapshot(address(agent), 0);

        uint256 totalDebt = _agentDebt(agent, perEpochRate);
        (, epochsPaid, principalPaid, refund) = agent.pay(0, sc);

        vm.stopPrank();

        Account memory account = AccountHelpers.getAccount(router, address(agent), 0);

        if (sc.vc.value >= totalDebt) {
            assertEq(
                account.epochsPaid,
                0,
                "Should have 0 epochs paid if there was a refund - meaning all principal was paid"
            );
            assertEq(
                account.principal, 0, "Should have 0 principal if there was a refund - meaning all principal was paid"
            );
        } else {
            assertGt(account.principal, 0, "Should have some principal left");
            assertGt(account.epochsPaid, prePayEpochsPaid, "Should have paid more epochs");
        }

        testInvariants("agentPay End");
    }

    function calculateInterestOwed(uint256 borrowAmount, uint256 rollFwdAmt, uint256 perEpochRate)
        internal
        pure
        returns (uint256 interestOwed, uint256 interestOwedPerEpoch)
    {
        // note we add 1 more bock of interest owed to account for the roll forward of 1 epoch inside agentBorrow helper
        // since borrowAmount is also WAD based, the _interestOwedPerEpoch is also WAD based (e18 * e18 / e18)
        uint256 _interestOwedPerEpoch = borrowAmount.mulWadUp(perEpochRate);
        // _interestOwedPerEpoch is mulWadUp by epochs (not WAD based), which cancels the WAD out for interestOwed
        interestOwed = (_interestOwedPerEpoch.mulWadUp(rollFwdAmt));
        // when setting the interestOwedPerEpoch, we div out the WAD manually here
        // we'd rather use the more precise _interestOwedPerEpoch to compute interestOwed above
        interestOwedPerEpoch = _interestOwedPerEpoch / WAD;
    }

    function putAgentOnAdministration(IAgent agent, address administration, uint256 rollFwdPeriod, uint256 borrowAmount)
        internal
    {
        IAgentPolice police = GetRoute.agentPolice(router);
        SignedCredential memory borrowCred = issueGenericBorrowCred(agent.id(), borrowAmount);

        agentBorrow(agent, borrowCred);

        vm.roll(block.number + rollFwdPeriod);

        vm.startPrank(IAuth(address(police)).owner());
        police.putAgentOnAdministration(
            address(agent), issueGenericPutOnAdministrationCred(agent.id(), borrowAmount), administration
        );
        vm.stopPrank();

        assertEq(agent.administration(), administration);
    }

    function setAgentDefaulted(IAgent agent, uint256 principal) internal {
        IAgentPolice police = GetRoute.agentPolice(router);
        SignedCredential memory defaultCred = issueGenericSetDefaultCred(agent.id(), principal);

        // set an account in storage with some principal
        agentBorrow(agent, issueGenericBorrowCred(agent.id(), principal));

        vm.startPrank(IAuth(address(police)).owner());
        police.setAgentDefaultDTL(address(agent), defaultCred);
        vm.stopPrank();

        testInvariants("setAgentDefaultDTL");

        assertTrue(agent.defaulted(), "Agent should be put into default");
    }

    function _agentOwner(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).owner();
    }

    function _agentOperator(IAgent agent) internal view returns (address) {
        return IAuth(address(agent)).operator();
    }

    function _snapshot(address agent, uint256 poolID) internal view returns (StateSnapshot memory snapshot) {
        Account memory account = AccountHelpers.getAccount(router, agent, poolID);
        snapshot.agentBalanceWFIL = wFIL.balanceOf(agent);
        snapshot.poolBalanceWFIL = wFIL.balanceOf(address(GetRoute.pool(GetRoute.poolRegistry(router), poolID)));
        snapshot.agentBorrowed = account.principal;
        snapshot.accountEpochsPaid = account.epochsPaid;
    }
}
