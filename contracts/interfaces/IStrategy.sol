//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

/**
 * @title The minimum a strategy needs
 */
interface IStrategy {
    function makeRequest() external;
    function strategy(bytes32 requestId, bytes calldata response) external;
}
