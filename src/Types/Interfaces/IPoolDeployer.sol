// Interface for the Pool Deployer contract
import {IPool} from "src/Types/Interfaces/IPool.sol";

interface IPoolDeployer {
    function deploy(
        uint256 _id,
        address _router,
        address _poolImplementation,
        address _asset,
        address _share,
        address _template,
        address _ramp,
        address _iou,
        uint256 _minimumLiquidity
    ) external returns (IPool);
}