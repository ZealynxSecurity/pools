// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {FilAddress} from "shim/FilAddress.sol";
import {PoolSnapshot} from "src/Upgrades/PoolSnapshot.sol";
import {Ownable} from "src/Auth/Ownable.sol";
import {GetRoute} from "src/Router/GetRoute.sol";
import {InfinityPool} from "src/Pool/InfinityPool.sol";
import {AgentPolice} from "src/Agent/AgentPolice.sol";
import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IPoolRegistry} from "src/Types/Interfaces/IPoolRegistry.sol";
import {ROUTE_AGENT_POLICE, ROUTE_INFINITY_POOL, ROUTE_POOL_REGISTRY} from "src/Constants/Routes.sol";

contract UpgradeToV2 is Ownable {
    using PoolSnapshot for IPool;
    using FilAddress for address;
    using FilAddress for address payable;

    address immutable router;

    string constant VERIFIED_NAME = "glif.io";
    string constant VERIFIED_VERSION = "1";

    event DeployedContracts(address indexed agentPolice, address indexed pool);

    constructor(address _router, address _owner) Ownable(_owner) {
        router = _router;
    }

    function deployContracts() external onlyOwner returns (address agentPolice, address pool) {
        IPoolRegistry poolRegistry = IPoolRegistry(GetRoute.poolRegistry(router));
        address oldPool = address(GetRoute.pool(poolRegistry, 0));
        IAuth oldAP = IAuth(address(GetRoute.agentPolice(router)));

        address lst = address(IPool(oldPool).liquidStakingToken());

        agentPolice = address(new AgentPolice(VERIFIED_NAME, VERIFIED_VERSION, oldAP.owner(), oldAP.operator(), router));

        pool = address(
            new InfinityPool(
                IAuth(address(oldPool)).owner(), router, lst, address(0), IPool(oldPool).minimumLiquidity(), 0
            )
        );

        emit DeployedContracts(agentPolice, pool);

        return (agentPolice, pool);
    }

    function upgrade(address agentPolice, address pool) external payable onlyOwner {
        address poolRegistry = address(GetRoute.poolRegistry(router));
        address oldPool = address(GetRoute.pool(IPoolRegistry(poolRegistry), 0));

        PoolSnapshot.PoolState memory oldPoolState = IPool(oldPool).snapshot();

        address lst = address(IPool(oldPool).liquidStakingToken());

        address oldPoolOwner = IAuth(oldPool).owner();
        address poolRegOwner = IAuth(poolRegistry).owner();
        address routerOwner = IAuth(router).owner();
        address lstOwner = IAuth(lst).owner();

        // temporarily accept ownership of the required protocol contracts to upgrade to V2
        IAuth(oldPool).acceptOwnership();
        IAuth(poolRegistry).acceptOwnership();
        IAuth(router).acceptOwnership();
        IAuth(lst).acceptOwnership();

        // first shut down the pool
        IPool(oldPool).shutDown();
        // then upgrade the pool
        IPoolRegistry(poolRegistry).upgradePool(IPool(pool));
        // set the minter and burner of iFIL to be the new pool
        IPoolToken(lst).setMinter(pool);
        IPoolToken(lst).setBurner(pool);
        // set the new routes
        IRouter(router).pushRoute(ROUTE_INFINITY_POOL, pool);
        IRouter(router).pushRoute(ROUTE_AGENT_POLICE, agentPolice);
        // set the new pool to be the new pool registry in the router (ending multipool)
        IRouter(router).pushRoute(ROUTE_POOL_REGISTRY, pool);

        // assign ownership back to the original owners
        IAuth(oldPool).transferOwnership(oldPoolOwner);
        IAuth(poolRegistry).transferOwnership(poolRegOwner);
        IAuth(router).transferOwnership(routerOwner);
        IAuth(lst).transferOwnership(lstOwner);

        // send a test deposit/withdraw if there was value in this message
        if (msg.value > 0) {
            uint256 depositAmnt = msg.value;
            uint256 iFILReceived = IPool(pool).deposit{value: depositAmnt}(address(this));
            require(iFILReceived > 0, "UpgradeToV2: deposit failed");

            IPoolToken(lst).approve(pool, iFILReceived);
            uint256 receivedFIL = IPool(pool).redeemF(iFILReceived, address(this), address(this));
            require(receivedFIL == depositAmnt, "UpgradeToV2: withdraw failed");

            payable(msg.sender).sendValue(depositAmnt);
        }

        // throws an error if theres an accounting mismatch
        IPool(pool).mustBeEqual(oldPoolState);
    }

    function refreshProtocolRoutes(address[] calldata agents) external {
        for (uint256 i = 0; i < agents.length; i++) {
            IAgent(agents[i]).refreshRoutes();
        }
    }

    function setOwner(IAuth _auth, address _newOwner) external onlyOwner {
        _auth.transferOwnership(_newOwner);
    }
}
