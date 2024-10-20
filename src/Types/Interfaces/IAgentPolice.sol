// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";
import {IPausable} from "src/Types/Interfaces/IPausable.sol";

interface IAgentPolice {
    /*//////////////////////////////////////////////
                    EVENT LOGS
    //////////////////////////////////////////////*/

    event Defaulted(address agent);

    event OnAdministration(address agent);

    event FaultySectors(address indexed agentID, uint256 faultEpoch);

    /*//////////////////////////////////////////////
                      ERRORS
    //////////////////////////////////////////////*/

    error AgentStateRejected();
    error LiquidationValueTooHigh();
    error OverLimitDTE();
    error OverLimitDTL();
    error OverLimitQuota();
    error OverFaultySectorLimit();
    error MaxMinersReached();

    /*//////////////////////////////////////////////
                      GETTERS
    //////////////////////////////////////////////*/

    function agentApproved(VerifiableCredential calldata vc) external;

    function agentLiquidated(uint256 agentID) external view returns (bool);

    function borrowDTL() external view returns (uint256);

    function liquidationDTL() external view returns (uint256);

    function liquidationFee() external view returns (uint256);

    function maxMiners() external view returns (uint32);

    function sectorFaultyTolerancePercent() external view returns (uint256);

    function levels(uint256 index) external view returns (uint256);

    function accountLevel(uint256 agentID) external view returns (uint256);

    /*//////////////////////////////////////////////
                    VC HANDLING
    //////////////////////////////////////////////*/

    function isValidCredential(uint256 agent, bytes4 action, SignedCredential calldata sc) external;

    function credentialUsed(VerifiableCredential calldata vc) external view returns (uint256);

    function registerCredentialUseBlock(SignedCredential calldata sc) external;

    /*//////////////////////////////////////////////
                      POLICING
    //////////////////////////////////////////////*/

    function putAgentOnAdministration(address agent, SignedCredential calldata sc, address administration) external;

    function setAgentDefaultDTL(address agent, SignedCredential calldata sc) external;

    function setSectorFaultyTolerancePercent(uint256 percent) external;

    function setLiquidationDTL(uint256 threshold) external;

    function setBorrowDTL(uint256 dtl) external;

    function setLiquidationFee(uint256 liquidationFee) external;

    function prepareMinerForLiquidation(address agent, uint64 miner, uint64 liquidator) external;

    function distributeLiquidatedFunds(address agent, uint256 amount) external;

    function confirmRmEquity(VerifiableCredential calldata vc) external view;

    function confirmRmAdministration(VerifiableCredential calldata vc) external view;

    /*//////////////////////////////////////////////
                  ADMIN CONTROLS
    //////////////////////////////////////////////*/

    function setLevels(uint256[10] calldata _levels) external;

    function setAgentLevels(uint256[] calldata agentIDs, uint256[] calldata level) external;

    function setMaxMiners(uint32 maxMiners) external;

    function pause() external;

    function unpause() external;
}
