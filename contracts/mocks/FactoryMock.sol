// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IFactory.sol";

/**
 * @title Mock of the core factory for ease testing
 */
contract FactoryMock is IFactoryDef {
    address private _kacyToken;
    uint private _minimumKacy;

    function setKacyToken(address newAddr)
        external
    {
        _kacyToken = newAddr;
    }

    function setKacyMinimum(uint percent)
        external
    {
        _minimumKacy = percent;
    }

    function kacyToken() external override view returns (address) {
        return _kacyToken;
    }

    function minimumKacy() external override view returns (uint) {
        return _minimumKacy;
    }
}