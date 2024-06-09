// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import {SignedCredential, VerifiableCredential} from "src/Types/Structs/Credentials.sol";
import {IAgent} from "src/Types/Interfaces/IAgent.sol";

interface IAgentPolice {
    /*//////////////////////////////////////////////
                    EVENT LOGS
    //////////////////////////////////////////////*/

    event Defaulted(address agent);

    event OnAdministration(address agent);

    event FaultySectors(address indexed agentID, uint256 faultEpoch);

    /*//////////////////////////////////////////////
                      GETTERS
    //////////////////////////////////////////////*/

    function administrationWindow() external view returns (uint256);

    function agentApproved(VerifiableCredential calldata vc) external;

    function agentLiquidated(uint256 agentID) external view returns (bool);

    function paused() external view returns (bool);

    function maxDTE() external view returns (uint256);

    function maxDTL() external view returns (uint256);

    function dtlLiquidationThreshold() external view returns (uint256);

    function maxDTI() external view returns (uint256);

    function sectorFaultyTolerancePercent() external view returns (uint256);

    /*//////////////////////////////////////////////
                    VC HANDLING
    //////////////////////////////////////////////*/

    function isValidCredential(uint256 agent, bytes4 action, SignedCredential calldata signedCredential) external;

    function credentialUsed(VerifiableCredential calldata vc) external view returns (bool);

    function registerCredentialUseBlock(SignedCredential calldata signedCredential) external;

    /*//////////////////////////////////////////////
                      POLICING
    //////////////////////////////////////////////*/

    function putAgentOnAdministration(address agent, address administration) external;

    function setAgentDefaultDTL(address agent, SignedCredential calldata vc) external;

    function setSectorFaultyTolerancePercent(uint256 percent) external;

    function setDtlLiquidationThreshold(uint256 threshold) external;

    function setMaxDTE(uint256 dte) external;

    function setMaxDTL(uint256 dtl) external;

    function setMaxDTI(uint256 dti) external;

    function setRiskParamsToMatchPool() external;

    function prepareMinerForLiquidation(address agent, uint64 miner, uint64 liquidator) external;

    function distributeLiquidatedFunds(address agent, uint256 amount) external;

    function confirmRmEquity(VerifiableCredential calldata vc) external view;

    function confirmRmAdministration(VerifiableCredential calldata vc) external view;

    /*//////////////////////////////////////////////
                  ADMIN CONTROLS
    //////////////////////////////////////////////*/

    function setAdministrationWindow(uint256 administrationWindow) external;

    function pause() external;

    function resume() external;
}
