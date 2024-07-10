// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolToken} from "./IPoolToken.sol";

// an interface with common methods for V1 and V2 pools
interface IMiniPool {
    function convertToShares(uint256) external view returns (uint256);

    function convertToAssets(uint256) external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalBorrowed() external view returns (uint256);

    function getAgentBorrowed(uint256) external view returns (uint256);

    function getRate() external view returns (uint256);

    function liquidStakingToken() external view returns (IPoolToken);
}
