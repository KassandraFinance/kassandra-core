// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IPool.sol";

interface IFactoryDef {
    function kacyToken() external view returns (address);
    function minimumKacy() external view returns (uint);
}

interface IFactory is IFactoryDef {
    function newPool() external returns (IPool pool);
}
