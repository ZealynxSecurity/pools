// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

// Interface for the Pool Deployer contract
import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolDeployer {
    function deploy(
        address _owner,
        address _operator,
        uint256 _id,
        address _router,
        address _asset,
        address _share,
        address _ramp,
        address _iou,
        uint256 _minimumLiquidity,
        uint256 _bias
    ) external returns (IPool);
}
