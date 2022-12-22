// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.15;

import "src/MockMiner.sol";
import {Authority} from "src/Auth/Auth.sol";
import {RoleAuthority} from "src/Auth/RoleAuthority.sol";
import {VCVerifier} from "src/VCVerifier/VCVerifier.sol";

import {IMultiRolesAuthority} from "src/Types/Interfaces/IMultiRolesAuthority.sol";
import {IERC20} from "src/Types/Interfaces/IERC20.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IMinerRegistry} from "src/Types/Interfaces/IMinerRegistry.sol";
import {IAgentFactory} from "src/Types/Interfaces/IAgentFactory.sol";
import {IPoolFactory} from "src/Types/Interfaces/IPoolFactory.sol";
import {IPool} from "src/Types/Interfaces/IPool.sol";
import {IPowerToken} from "src/Types/Interfaces/IPowerToken.sol";
import {IRouter} from "src/Types/Interfaces/IRouter.sol";
import {IStats} from "src/Types/Interfaces/IStats.sol";
import {VerifiableCredential} from "src/Types/Structs/Credentials.sol";

import {
  ROUTE_AGENT_FACTORY,
  ROUTE_POWER_TOKEN,
  ROUTE_POOL_FACTORY,
  ROUTE_MINER_REGISTRY,
  ROUTE_STATS } from "src/Constants/Routes.sol";
import {ROLE_AGENT_OPERATOR, ROLE_AGENT_OWNER} from "src/Constants/Roles.sol";

contract Agent is IAgent, VCVerifier {
  address[] public override miners;
  mapping(address => bool) public hasMiner;
  uint256 powerTokensMinted = 0;
  bool redZone = false;

  /*//////////////////////////////////////
                MODIFIERS
  //////////////////////////////////////*/

  modifier requiresAuth() virtual {
    require(RoleAuthority.canCallSubAuthority(router, address(this)), "Agent: Not authorized");
    _;
  }

  constructor(address _router, string memory _name, string memory _version)
    VCVerifier(_name, _version) {
    router = _router;
  }

  /*//////////////////////////////////////////////////
                MINER OWNERSHIP CHANGES
  //////////////////////////////////////////////////*/

  function addMiner(address miner) external requiresAuth {
    _addMiner(miner);
  }

  function removeMiner(address miner) external requiresAuth {
    for (uint256 i = 0; i < miners.length; i++) {
      if (miners[i] == miner) {
        _removeMiner(i);
        break;
      }
    }
  }

  function removeMiner(uint256 index) external requiresAuth {
    _removeMiner(index);
  }

  function minerCount() external view returns (uint256) {
    return miners.length;
  }

  function revokeOwnership(address newOwner, address miner) public requiresAuth {
    require(IMiner(miner).currentOwner() == address(this), "Agent does not own miner");
    require(!IStats(IRouter(router).getRoute(ROUTE_STATS)).isDebtor(address(this)), "Cannot revoke miner ownership with outstanding loans");
    IMiner(miner).changeOwnerAddress(newOwner);
    IAgentFactory(IRouter(router).getRoute(ROUTE_AGENT_FACTORY)).revokeOwnership(address(this));
  }

  function enableOperator(address newOperator) external requiresAuth {
    IMultiRolesAuthority(
      address(RoleAuthority.getSubAuthority(router, address(this)))
    ).setUserRole(newOperator, ROLE_AGENT_OPERATOR, true);
  }

  function disableOperator(address operator) external requiresAuth {
    IMultiRolesAuthority(
      address(RoleAuthority.getSubAuthority(router, address(this)))
    ).setUserRole(operator, ROLE_AGENT_OPERATOR, false);
  }

  function enableOwner(address newOwner) external requiresAuth {
    IMultiRolesAuthority(
      address(RoleAuthority.getSubAuthority(router, address(this)))
    ).setUserRole(newOwner, ROLE_AGENT_OWNER, true);
  }

  function disableOwner(address owner) external requiresAuth {
    IMultiRolesAuthority(
      address(RoleAuthority.getSubAuthority(router, address(this)))
    ).setUserRole(owner, ROLE_AGENT_OWNER, false);
  }

  /*//////////////////////////////////////////////////
                POWER TOKEN FUNCTIONS
  //////////////////////////////////////////////////*/

  function mintPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external requiresAuth {
    require(!redZone, "Agent: Cannot mint power while Agent is in the red zone");
    require(isValid(vc, v, r, s), "Invalid VC");
    require(vc.miner.qaPower >= powerTokensMinted + amount, "Cannot mint more power than the miner has");

    IPowerToken(IRouter(router).getRoute(ROUTE_POWER_TOKEN)).mint(amount);
    powerTokensMinted += amount;
  }

  function burnPower(uint256 amount, VerifiableCredential memory vc, uint8 v, bytes32 r, bytes32 s) external requiresAuth {
    require(isValid(vc, v, r, s), "Invalid VC");
    IERC20 powerToken = IERC20(IRouter(router).getRoute(ROUTE_POWER_TOKEN));
    require(amount <= powerToken.balanceOf(address(this)), "Agent: Cannot burn more power than the agent holds");

    IPowerToken(address(powerToken)).burn(amount);
    powerTokensMinted -= amount;
  }

  /*//////////////////////////////////////////////
                FINANCIAL FUNCTIONS
  //////////////////////////////////////////////*/
  function withdrawBalance(address miner) external requiresAuth returns (uint256) {
    return IMiner(miner).withdrawBalance(0);
  }

  function borrow(
    uint256 amount,
    uint256 poolID,
    VerifiableCredential memory vc,
    uint256 powerTokenAmount,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external requiresAuth {
    require(isValid(vc, v, r, s), "Invalid VC");
    _getPool(poolID).borrow(amount, vc, powerTokenAmount);
  }

  function exit(
    uint256 poolID,
    VerifiableCredential memory vc,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external requiresAuth {
    require(isValid(vc, v, r, s), "Invalid VC");
    IPool pool = _getPool(poolID);
    uint256 amount = pool.getAgentBorrowed(address(this));
    pool.getAsset().approve(address(pool), amount);
    pool.exitPool(amount, vc);
  }

  function makePayment(uint256 poolID, VerifiableCredential memory vc) external requiresAuth {
    // TODO: validate VC here and pay off all other pools
    _getPool(poolID).makePayment(address(this), vc);
  }

  /*//////////////////////////////////////////////
                INTERNAL FUNCTIONS
  //////////////////////////////////////////////*/

  function _getPool(uint256 poolID) internal view returns (IPool) {
    IPoolFactory poolFactory = IPoolFactory(IRouter(router).getRoute(ROUTE_POOL_FACTORY));
    require(poolID <= poolFactory.allPoolsLength(), "Invalid pool ID");
    address pool = poolFactory.allPools(poolID);
    return IPool(pool);
  }

  function _addMiner(address miner) internal {
    require(hasMiner[miner] == false, "Miner already added");
    IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY)).addMiner(miner);
    hasMiner[miner] = true;
    _claimOwnership(miner);
    miners.push(miner);
  }

  function _removeMiner(uint256 index) internal {
    // Confirm the miner is valid and can be removed
    require(index < miners.length, "Invalid index");
    require(_canRemoveMiner(index), "Cannot remove miner unless all loans are paid off or it isn't needed for collateral");

    // Remove the miner from the central registry
    IMinerRegistry(IRouter(router).getRoute(ROUTE_MINER_REGISTRY)).removeMiner(miners[index]);

    // Update state to reflect the miner removal
    hasMiner[miners[index]] = false;
    revokeOwnership(msg.sender, miners[index]);
    miners[index] = miners[miners.length - 1];
    miners.pop();
  }

  function _claimOwnership(address miner) internal {
    IMiner(miner).changeOwnerAddress(address(this));
  }

  function _canRemoveMiner(uint256 index) internal view returns (bool) {
    return !IStats(IRouter(router).getRoute(ROUTE_STATS)).isDebtor(address(this)) || _evaluateCollateral(index);
  }

  function _evaluateCollateral(uint256 index) internal view returns (bool) {
    return true;
  }

  fallback() external payable {  }
}

