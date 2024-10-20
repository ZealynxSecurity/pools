// SPDX-License-Identifier: UNLICENSED
// solhint-disable private-vars-leading-underscore, var-name-mixedcase
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {MinerHelper} from "shim/MinerHelper.sol";
import {PoolToken} from "shim/PoolToken.sol";
import {WFIL} from "shim/WFIL.sol";

import {UpgradeToV2} from "src/Upgrades/UpgradeToV2.sol";
import {InfinityPoolV2} from "src/Pool/InfinityPoolV2.sol";
import {AgentPoliceV2} from "src/Agent/AgentPoliceV2.sol";
import {Router} from "src/Router/Router.sol";
import {EPOCHS_IN_WEEK} from "src/Constants/Epochs.sol";
import {AgentData, Credentials, SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {Account} from "src/Types/Structs/Account.sol";

import {GetRoute} from "v0/Router/GetRoute.sol";
import {AccountHelpers} from "v0/Pool/Account.sol";
import {Agent} from "v0/Agent/Agent.sol";
import {AgentFactory} from "v0/Agent/AgentFactory.sol";
import {AgentDeployer} from "v0/Agent/AgentDeployer.sol";
import {AgentPolice} from "v0/Agent/AgentPolice.sol";
import {MinerRegistry} from "v0/Agent/MinerRegistry.sol";
import {AuthController} from "v0/Auth/AuthController.sol";
import {PoolRegistry} from "v0/Pool/PoolRegistry.sol";
import {SimpleRamp} from "v0/OffRamp/OffRamp.sol";
import {RateModule} from "v0/Pool/RateModule.sol";
import {InfinityPool} from "v0/Pool/InfinityPool.sol";
import {CredParser} from "v0/Credentials/CredParser.sol";

import {IAuth} from "src/Types/Interfaces/IAuth.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IWFIL} from "src/Types/Interfaces/IWFIL.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IPoolToken} from "src/Types/Interfaces/IPoolToken.sol";
import {IAgentPolice} from "src/Types/Interfaces/IAgentPolice.sol";
import {IPoolRegistry} from "v0/Types/Interfaces/IPoolRegistry.sol";
import {IPool} from "v0/Types/Interfaces/IPool.sol";
import {IOffRamp} from "v0/Types/Interfaces/IOffRamp.sol";
import {IInfinityPool} from "v0/Types/Interfaces/IInfinityPool.sol";

import {CoreTestHelper} from "test/helpers/CoreTestHelper.sol";
import {AgentTestHelper} from "test/helpers/AgentTestHelper.sol";
import {PoolTestHelper} from "test/helpers/PoolTestHelper.sol";
import {Deployer} from "test/helpers/DeployerV1.sol";
import {PreStake} from "test/helpers/PreStake.sol";
import {MockMiner} from "test/helpers/MockMiner.sol";
import {EPOCHS_IN_WEEK, EPOCHS_IN_DAY, EPOCHS_IN_YEAR} from "src/Constants/Epochs.sol";
import "test/helpers/Constants.sol";

interface IPoolV2 {
    function getAgentDebt(uint256 agentID) external view returns (uint256);
}

contract UpgradeTest is CoreTestHelper, PoolTestHelper, AgentTestHelper {
    uint256 public constant DEFAULT_WINDOW = EPOCHS_IN_WEEK * 3;

    IPool oldPool;
    IOffRamp ramp;
    IAgentFactory agentFactory;
    UpgradeToV2 upgrader;

    IAgent agent;
    address agentOwner = makeAddr("AGENT_OWNER");
    address investor = makeAddr("INVESTOR");
    address agentPolice;
    address pool;

    constructor() {
        vm.startPrank(systemAdmin);
        // deploys the router
        router = address(new Router(systemAdmin));

        agentFactory = IAgentFactory(address(new AgentFactory(router)));
        // 1e17 = 10% treasury fee on yield
        address poolRegistry = address(new PoolRegistry(10e16, systemAdmin, router));

        Deployer.setupContractRoutes(
            address(router),
            treasury,
            address(wFIL),
            address(new MinerRegistry(router, IAgentFactory(agentFactory))),
            address(agentFactory),
            address(
                new AgentPolice(
                    VERIFIED_NAME,
                    VERIFIED_VERSION,
                    DEFAULT_WINDOW,
                    systemAdmin,
                    systemAdmin,
                    router,
                    IPoolRegistry(poolRegistry),
                    IWFIL(address(wFIL))
                )
            ),
            poolRegistry,
            vcIssuer,
            credParser,
            address(new AgentDeployer())
        );
        // roll forward at least 1 window length so our computations dont overflow/underflow
        vm.roll(block.number + DEFAULT_WINDOW);

        iFIL = IPoolToken(address(new PoolToken(systemAdmin)));
        oldPool = IPool(
            new InfinityPool(
                systemAdmin,
                router,
                address(wFIL),
                address(new RateModule(systemAdmin, router, rateArray, levels)),
                // no min liquidity for test oldPool
                address(iFIL),
                address(new PreStake(systemAdmin, IWFIL(address(wFIL)), iFIL)),
                0,
                GetRoute.poolRegistry(router).allPoolsLength()
            )
        );

        IPoolRegistry(poolRegistry).attachPool(oldPool);

        ramp = new SimpleRamp(router, oldPool.id());

        oldPool.setRamp(ramp);

        iFIL.setMinter(address(oldPool));
        iFIL.setBurner(address(ramp));

        vm.stopPrank();
        // deposit 1e18 FIL to the pool to avoid a donation attack
        address donator = makeAddr("DONATOR");
        _depositFundsIntoPool(1e18, donator);
    }

    function setUp() public {
        _depositFundsIntoPool(1e18, investor);
        _withdrawFILFromPool(investor, address(ramp), 1e18);
        (agent,) = configureAgent(agentOwner);
        SignedCredential memory sc = _issueGenericBorrowCred(agent.id(), 1e18);
        vm.prank(agentOwner);
        agent.borrow(0, sc);

        // deploy the new contracts
        (agentPolice, pool) = _deployContracts();

        // deploy the upgrader
        upgrader = new UpgradeToV2(router, systemAdmin);

        // set up another 169 agents for testing to get more accurate gas stats
        _configureManyAgents();
    }

    function testUpgradeV1ToV2() public {
        // move forward to generate some interest
        vm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwedOnAccount = _agentInterest(agent, _getAdjustedRate());
        assertGt(interestOwedOnAccount, 0, "Interest owed should be greater than 0");

        // maintain a handle on the original pool registry and rate module because they get overwritten
        (address poolRegistry, address rateModule) = _transferOwnershipOfContracts(address(upgrader));

        vm.deal(systemAdmin, 1e18);

        uint256 systemAdminBal = systemAdmin.balance;

        vm.prank(systemAdmin);
        upgrader.upgrade{value: 1e18}(agentPolice, pool);

        assertEq(systemAdminBal, systemAdmin.balance, "System admin balance should not change after upgrade");

        _depositFundsIntoPool(1e18, investor);
        _withdrawFILFromPool(investor, pool, IPool(pool).maxWithdraw(investor));

        uint256 poolTotalAssets = IPool(pool).totalAssets();

        // make a payment to make sure new agent police is working and pool accounting is working
        // here we test a full exist to make sure there is no refund
        SignedCredential memory sc = _issueGenericPayCred(agent.id(), IPoolV2(pool).getAgentDebt(agent.id()));
        vm.deal(address(agent), 1e18);
        vm.startPrank(agentOwner);

        // first attempt should fail because agent has not refreshed routes
        vm.expectRevert();
        agent.pay(0, sc);

        agent.refreshRoutes();
        agent.pay(0, sc);

        // making a payment should not change the total assets of the pool in v2
        assertEq(IPool(pool).totalAssets(), poolTotalAssets, "Total assets should not change after payment");

        // make a random call to the new agent police that did not exist on hte old one to make sure the new one is deployed
        uint256 testVal = IAgentPolice(agentPolice).liquidationDTL();
        assertGt(testVal, 0, "Agent police liquidation threshold should have a value");

        // try to borrow
        sc = _issueGenericBorrowCred(agent.id(), 1e18);
        _fundAgentsMiners(agent, sc.vc);
        vm.startPrank(agentOwner);
        agent.borrow(0, sc);
        vm.stopPrank();

        _approveOwnershipOfContracts(poolRegistry, rateModule);
    }

    function testUpgradeManyAgents() public {
        uint256 numAgents = 170;

        vm.roll(block.number + EPOCHS_IN_YEAR);

        uint256 interestOwedOnAccounts = _agentInterest(agent, _getAdjustedRate()) * numAgents;

        uint256 totalAssetsOldPool = oldPool.totalAssets();
        uint256 totalLiquid = oldPool.getLiquidAssets();

        _transferOwnershipOfContracts(address(upgrader));

        vm.prank(systemAdmin);
        upgrader.upgrade(agentPolice, pool);

        uint256 totalAssetsNewPool = IPool(pool).totalAssets();

        assertEq(
            totalAssetsOldPool + interestOwedOnAccounts,
            totalAssetsNewPool,
            "Total assets should increase by unpaid interest"
        );
        assertEq(totalLiquid, IPool(pool).getLiquidAssets(), "Liquid assets should remain the same after upgrade");
    }

    function _configureManyAgents() internal returns (uint256 numAgents) {
        numAgents = 170;
        // deposit enough funds to cover the borrow amounts of 170 agents
        uint256 borrowAmount = 1e18;
        _depositFundsIntoPool(borrowAmount * numAgents, investor);

        // subract 1 from num agents to account for the agent we already have
        for (uint256 i = 0; i < numAgents - 1; i++) {
            (IAgent agent,) = configureAgent(agentOwner);
            SignedCredential memory sc = _issueGenericBorrowCred(agent.id(), 1e18);
            vm.prank(agentOwner);
            agent.borrow(0, sc);
        }
    }

    function _deployContracts() internal returns (address agentPolice, address pool) {
        IAuth oldAP = IAuth(address(GetRoute.agentPolice(router)));

        address lst = address(IPool(oldPool).liquidStakingToken());

        agentPolice =
            address(new AgentPoliceV2(VERIFIED_NAME, VERIFIED_VERSION, oldAP.owner(), oldAP.operator(), router));

        pool = address(
            new InfinityPoolV2(
                IAuth(address(oldPool)).owner(), router, lst, address(0), IPool(oldPool).minimumLiquidity(), 0
            )
        );

        assertTrue(agentPolice != address(0), "Agent police deploy failed");
        assertTrue(pool != address(0), "Pool deploy failed");

        return (agentPolice, pool);
    }

    function _transferOwnershipOfContracts(address upgrader)
        internal
        returns (address poolRegistry, address rateModule)
    {
        vm.startPrank(systemAdmin);
        poolRegistry = address(GetRoute.poolRegistry(router));
        rateModule = address(IInfinityPool(address(oldPool)).rateModule());
        // assign the pool registry, router, lst, and old pool ownership to this contract
        IAuth(address(oldPool)).transferOwnership(address(upgrader));
        IAuth(router).transferOwnership(address(upgrader));
        IAuth(address(iFIL)).transferOwnership(address(upgrader));
        IAuth(poolRegistry).transferOwnership(address(upgrader));
        IAuth(rateModule).transferOwnership(address(upgrader));
        vm.stopPrank();
    }

    function _approveOwnershipOfContracts(address poolRegistry, address rateModule) internal {
        vm.startPrank(systemAdmin);
        IAuth(address(oldPool)).acceptOwnership();
        IAuth(router).acceptOwnership();
        IAuth(address(iFIL)).acceptOwnership();
        IAuth(poolRegistry).acceptOwnership();
        IAuth(rateModule).acceptOwnership();
        vm.stopPrank();
    }

    function _withdrawFILFromPool(address _investor, address _pool, uint256 amount) internal {
        uint256 investorBalBefore = wFIL.balanceOf(_investor) + payable(address(_investor)).balance;
        vm.startPrank(_investor);
        iFIL.approve(_pool, amount);
        IOffRamp(_pool).withdrawF(amount, _investor, _investor, 0);

        assertEq(
            investorBalBefore + amount,
            wFIL.balanceOf(_investor) + payable(address(_investor)).balance,
            "Investor balance should increase by amount"
        );
        vm.stopPrank();
    }

    uint256[61] rateArray = [
        2113986132250972433409436834094,
        2087561305597835277777777777777,
        2061136478944698122146118721461,
        2034711652291560966514459665144,
        2008286825638423811834094368340,
        1981861998985286656202435312024,
        1955437172332149500570776255707,
        1929012345679012344939117199391,
        1902587519025875190258751902587,
        1876162692372738034627092846270,
        1796888212413326567732115677321,
        1770463385760189413051750380517,
        1744038559107052257420091324200,
        1717613732453915101788432267884,
        1691188905800777946156773211567,
        1664764079147640791476407914764,
        1638339252494503635844748858447,
        1611914425841366480213089802130,
        1585489599188229324581430745814,
        1559064772535092168949771689497,
        1532639945881955014269406392694,
        1511500084559445289193302891933,
        1490360223236935565068493150684,
        1469220361914425840943683409436,
        1448080500591916116818873668188,
        1426940639269406392694063926940,
        1405800777946896667617960426179,
        1384660916624386943493150684931,
        1363521055301877219368340943683,
        1342381193979367495243531202435,
        1321241332656857770167427701674,
        1305386436664975477549467275494,
        1289531540673093183980213089802,
        1273676644681210890410958904109,
        1257821748689328597792998477929,
        1241966852697446304223744292237,
        1226111956705564010654490106544,
        1210257060713681718036529680365,
        1194402164721799424467275494672,
        1178547268729917130898021308980,
        1162692372738034838280060882800,
        1152122442076779976217656012176,
        1141552511415525114155251141552,
        1130982580754270251141552511415,
        1120412650093015389079147640791,
        1056993066125486216704718417047,
        1099272788770505664954337899543,
        1088702858109250802891933028919,
        1078132927447995940829528158295,
        1067562996786741078767123287671,
        1056993066125486216704718417047,
        1046423135464231354642313546423,
        1035853204802976491628614916286,
        1025283274141721629566210045662,
        1014713343480466767503805175038,
        1004143412819211905441400304414,
        993573482157957043378995433789,
        983003551496702181316590563165,
        972433620835447319254185692541,
        961863690174192457191780821917,
        951293759512937595129375951293
    ];
}
