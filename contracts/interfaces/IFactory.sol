// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./IPool.sol";

/**
 * @title Core factory definition interface
 */
interface IFactoryDef {
    function kacyToken() external view returns (address);
    function minimumKacy() external view returns (uint);
}

/**
 * @title Core factory interface with `newPool` as `IPool`
 *
 * @dev If `newPool` must be called and an interface must be returned this interface does that
 */
interface IFactory is IFactoryDef {
    function newPool() external returns (IPool pool);
}
