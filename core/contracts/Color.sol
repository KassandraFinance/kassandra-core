// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

abstract contract Color {
    function getColor() external pure virtual returns (bytes32);
}

abstract contract Bronze is Color {
    function getColor() external pure override returns (bytes32) {
        return bytes32("BRONZE");
    }
}
