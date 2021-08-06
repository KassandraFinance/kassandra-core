// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IMath.sol";

interface IPoolDef {
    function setSwapFee(uint swapFee) external;
    function setPublicSwap(bool publicSwap) external;
    function bind(address token, uint balance, uint denorm) external;
    function unbind(address token) external;
    function rebind(address token, uint balance, uint denorm) external;

    function isPublicSwap() external view returns (bool);
    function isBound(address token) external view returns(bool);
    function getCurrentTokens() external view returns (address[] memory tokens);
    function getDenormalizedWeight(address token) external view returns (uint);
    function getTotalDenormalizedWeight() external view returns (uint);
    function getNormalizedWeight(address token) external view returns (uint);
    function getBalance(address token) external view returns (uint);
    function getSwapFee() external view returns (uint);
}

interface IPool is IPoolDef, IMath {}
