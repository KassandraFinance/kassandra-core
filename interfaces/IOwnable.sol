// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// Introduce to avoid circularity (otherwise, the CRP and SmartPoolManager include each other)
// Removing circularity allows flattener tools to work, which enables Etherscan verification
interface IOwnable {
    function getController() external view returns (address);
}
