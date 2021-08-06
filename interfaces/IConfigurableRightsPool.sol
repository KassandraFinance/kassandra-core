// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// Interface declarations
import "./IPool.sol";
import "./IOwnable.sol";
import "./IERC20.sol";

// Introduce to avoid circularity (otherwise, the CRP and SmartPoolManager include each other)
// Removing circularity allows flattener tools to work, which enables Etherscan verification
interface IConfigurableRightsPoolDef {
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

interface IConfigurableRightsPool is IConfigurableRightsPoolDef, IOwnable, IERC20 {}
