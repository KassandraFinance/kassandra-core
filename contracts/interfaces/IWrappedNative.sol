// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title An interface for wrapped native tokens
 */
interface IWrappedNative {
    // Wraps the native tokens for an ERC-20 compatible token
    function deposit() external payable;

    // Unwraps the ERC-20 tokens to native tokens
    function withdraw(uint wad) external;
}
