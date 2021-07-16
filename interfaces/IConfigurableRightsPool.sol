// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// Interface declarations
import "./IFactory.sol";

// Introduce to avoid circularity (otherwise, the CRP and SmartPoolManager include each other)
// Removing circularity allows flattener tools to work, which enables Etherscan verification
interface IConfigurableRightsPool {
    function mintPoolShareFromLib(uint amount) external;
    function pushPoolShareFromLib(address to, uint amount) external;
    function pullPoolShareFromLib(address from, uint amount) external;
    function burnPoolShareFromLib(uint amount) external;
    function totalSupply() external view returns (uint);
    function corePool() external view returns(IPool);
    function getController() external view returns (address);
    function commitAddToken(address token, uint balance, uint denormalizedWeight) external;
    function applyAddToken() external;
    function removeToken(address token) external;
    function pokeWeights() external;
    function updateWeightsGradually(uint[] calldata newWeights, uint startBlock, uint endBlock) external;
}
