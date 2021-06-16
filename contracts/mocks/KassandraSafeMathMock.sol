// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Imports

import "../../libraries/KassandraSafeMath.sol";

// Contracts

/*
 * @author Balancer Labs
 * @title Wrap BalancerSafeMath for testing
*/
contract KassandraSafeMathMock {
    function bmul(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bmul(a, b);
    }

    function bdiv(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bdiv(a, b);
    }

    function bmod(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bmod(a, b);
    }

    function bmax(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bmax(a, b);
    }

    function bmin(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bmin(a, b);
    }

    function baverage(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.baverage(a, b);
    }

    function bpow(uint a, uint b) external pure returns (uint) {
        return KassandraSafeMath.bpow(a, b);
    }
}