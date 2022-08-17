// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IPool.sol";
import "./IOwnable.sol";
import "./IERC20.sol";

/**
 * @title CRPool definition interface
 *
 * @dev Introduce to avoid circularity (otherwise, the CRP and SmartPoolManager include each other)
 *      Removing circularity allows flattener tools to work, which enables Etherscan verification
 *      Only contains the definitions of the ConfigurableRigthsPool.sol contract and no parent classes
 */
interface IConfigurableRightsPoolDef {
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn) external;
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external;

    function joinswapExternAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut
    )
        external
        returns (uint poolAmountOut);

    function joinswapPoolAmountOut(
        address tokenIn,
        uint poolAmountOut,
        uint maxAmountIn
    )
        external
        returns (uint tokenAmountIn);

    function exitswapPoolAmountIn(
        address tokenOut,
        uint poolAmountIn,
        uint minAmountOut
    )
        external
        returns (uint tokenAmountOut);

    function exitswapExternAmountOut(
        address tokenOut,
        uint tokenAmountOut,
        uint maxPoolAmountIn
    )
        external
        returns (uint poolAmountIn);

    function updateWeight(address token, uint newWeight) external;
    function updateWeightsGradually(uint[] calldata newWeights, uint startBlock, uint endBlock) external;
    function pokeWeights() external;
    function commitAddToken(address token, uint balance, uint denormalizedWeight) external;
    function applyAddToken() external;
    function removeToken(address token) external;
    function mintPoolShareFromLib(uint amount) external;
    function pushPoolShareFromLib(address to, uint amount) external;
    function pullPoolShareFromLib(address from, uint amount) external;
    function burnPoolShareFromLib(uint amount) external;

    function corePool() external view returns(IPool);
}

/**
 * @title CRPool interface for external contracts
 *
 * @dev Joins the CRPool definition and the token and ownable interfaces
 */
interface IConfigurableRightsPool is IConfigurableRightsPoolDef, IOwnable, IERC20 {}
