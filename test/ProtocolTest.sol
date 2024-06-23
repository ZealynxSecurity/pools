// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {CoreTestHelper} from "test/helpers/CoreTestHelper.sol";
import {PoolTestHelper} from "test/helpers/PoolTestHelper.sol";
import {AgentTestHelper} from "test/helpers/AgentTestHelper.sol";
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
import {Router} from "src/Router/Router.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
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
import {EPOCHS_IN_DAY, EPOCHS_IN_WEEK, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

import "src/Constants/Routes.sol";
import "test/helpers/Constants.sol";

contract ProtocolTest is CoreTestHelper, PoolTestHelper, AgentTestHelper {
    using MinerHelper for uint64;
    using AccountHelpers for Account;
    using Credentials for VerifiableCredential;
    using FixedPointMathLib for uint256;

    uint256 public DEFAULT_BASE_RATE = FixedPointMathLib.divWadDown(15e16, EPOCHS_IN_YEAR * 1e18);

    IPool public pool;

    constructor() {
        vm.startPrank(systemAdmin);
        // deploys the router
        router = address(new Router(systemAdmin));
        IRouter(router).pushRoute(ROUTE_WFIL_TOKEN, address(wFIL));

        address agentFactory = address(new AgentFactory(router));

        Deployer.setupContractRoutes(
            address(router),
            treasury,
            address(wFIL),
            address(new MinerRegistry(router, IAgentFactory(agentFactory))),
            agentFactory,
            address(new AgentPoliceV2(VERIFIED_NAME, VERIFIED_VERSION, systemAdmin, systemAdmin, router)),
            vcIssuer,
            credParser,
            address(new AgentDeployer())
        );

        GetRoute.agentPolice(router).setLevels(CoreTestHelper.levels);

        vm.stopPrank();
        // roll forward at least 1 week so our computations dont overflow/underflow
        vm.roll(block.number + EPOCHS_IN_WEEK);

        pool = createPool();
    }

    // wraps the underlying _agentPay function with the V2 pool rate
    function agentPay(IAgent agent, SignedCredential memory sc)
        internal
        returns (uint256 epochsPaid, uint256 principalPaid, uint256 refund, StateSnapshot memory prePayState)
    {
        return _agentPay(agent, sc, _getAdjustedRate());
    }

    function _loadApproveWFIL(uint256 amount, address investor) internal {
        vm.deal(investor, amount);
        vm.startPrank(investor);
        wFIL.deposit{value: amount}();
        wFIL.approve(address(pool), amount);
        vm.stopPrank();
    }
}
