// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Authority} from "src/Auth/Auth.sol";

/// @notice Flexible and target agnostic role based Authority that supports up to 256 roles.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/auth/authorities/MultiRolesAuthority.sol)
interface IMultiRolesAuthority {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event UserRoleUpdated(address indexed user, uint8 indexed role, bool enabled);

    event PublicCapabilityUpdated(bytes4 indexed functionSig, bool enabled);

    event RoleCapabilityUpdated(uint8 indexed role, bytes4 indexed functionSig, bool enabled);

    event TargetCustomAuthorityUpdated(address indexed target, Authority indexed authority);

    /*//////////////////////////////////////////////////////////////
                            ROLE/USER STORAGE
    //////////////////////////////////////////////////////////////*/

    function doesUserHaveRole(address user, uint8 role) external view returns (bool);

    function doesRoleHaveCapability(uint8 role, bytes4 functionSig) external view returns (bool);

    function getTargetCustomAuthority(address target) external view returns (Authority);

    function getUserRoles(address user) external view returns (bytes32);

    function isCapabilityPublic(bytes4 capability) external view returns (bool);

    function getRolesWithCapability(bytes4 capability) external view returns (bytes32);


    /*//////////////////////////////////////////////////////////////
                           AUTHORIZATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) external view returns (bool);

    /*///////////////////////////////////////////////////////////////
               CUSTOM TARGET AUTHORITY CONFIGURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function setTargetCustomAuthority(address target, Authority customAuthority) external;

    /*//////////////////////////////////////////////////////////////
                  PUBLIC CAPABILITY CONFIGURATION LOGIC
    //////////////////////////////////////////////////////////////*/

    function setPublicCapability(bytes4 functionSig, bool enabled) external;

    /*//////////////////////////////////////////////////////////////
                       USER ROLE ASSIGNMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    function setRoleCapability( uint8 role, bytes4 functionSig, bool enabled) external;

    function setUserRole(address user, uint8 role, bool enabled) external;
}
