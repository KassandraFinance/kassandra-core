// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title CRP Factory interface for checking pools
 */
interface IcrpFactory {
    function isCrp(address addr) external view returns (bool);
}
