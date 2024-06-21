// SPDX-License-Identifier: BUSL-1.1
// solhint-disable private-vars-leading-underscore, var-name-mixedcase

pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {PoolToken} from "shim/PoolToken.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {InfinityPool} from "src/Pool/InfinityPool.sol";

import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {ILiquidityMineSP} from "src/Types/Interfaces/ILiquidityMineSP.sol";
import {IVCVerifier} from "src/Types/Interfaces/IVCVerifier.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {Account} from "src/Types/Structs/Account.sol";
import {AgentData, VerifiableCredential, SignedCredential} from "src/Types/Structs/Credentials.sol";
import {CredParser} from "src/Credentials/CredParser.sol";
import {IERC4626} from "src/Types/Interfaces/IERC4626.sol";
import {EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";

import {CoreTestHelper} from "test/helpers/CoreTestHelper.sol";
import {AgentTestHelper} from "test/helpers/AgentTestHelper.sol";
import {MockMiner} from "test/helpers/MockMiner.sol";
import "src/Constants/Routes.sol";
import "test/helpers/Constants.sol";

contract PoolTestHelper is CoreTestHelper {
    function createPool() internal returns (IPool) {
        PoolToken liquidStakingToken = new PoolToken(systemAdmin);
        IPool _pool = IPool(
            new InfinityPool(
                systemAdmin,
                router,
                // no min liquidity for test pool
                address(liquidStakingToken),
                ILiquidityMineSP(address(0)),
                0,
                0
            )
        );
        vm.startPrank(systemAdmin);
        liquidStakingToken.setMinter(address(_pool));
        liquidStakingToken.setBurner(address(_pool));
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, address(_pool));
        IRouter(router).pushRoute(ROUTE_POOL_REGISTRY, address(_pool));
        vm.stopPrank();

        return _pool;
    }

    function depositFundsIntoPool(uint256 amount, address investor) internal {
        address pool = address(GetRoute.pool(GetRoute.poolRegistry(router), 0));
        IERC4626 pool4626 = IERC4626(address(pool));
        // `investor` stakes `amount` FIL
        vm.deal(investor, amount);
        vm.startPrank(investor);
        wFIL.deposit{value: amount}();
        wFIL.approve(address(pool), amount);
        pool4626.deposit(amount, investor);
        vm.stopPrank();
    }
}
