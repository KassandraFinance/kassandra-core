// SPDX-License-Identifier: GPL3-or-later
pragma solidity ^0.8.0;

import "../../libraries/KassandraConstants.sol";

/*
 * @title Wrap KassandraConstant for tests
*/
contract KassandraConstantsMock {
    // solhint-disable func-name-mixedcase
    function ONE() public pure returns (uint) {
        return KassandraConstants.ONE;
    }
    function MIN_WEIGHT() public pure returns (uint) {
        return KassandraConstants.MIN_WEIGHT;
    }
    function MAX_WEIGHT() public pure returns (uint) {
        return KassandraConstants.MAX_WEIGHT;
    }
    function MAX_TOTAL_WEIGHT() public pure returns (uint) {
        return KassandraConstants.MAX_TOTAL_WEIGHT;
    }
    function MIN_BALANCE() public pure returns (uint) {
        return KassandraConstants.MIN_BALANCE;
    }
    /*function MAX_BALANCE() public pure returns (uint) {
        return KassandraConstants.MAX_BALANCE;
    }*/
    function MIN_POOL_SUPPLY() public pure returns (uint) {
        return KassandraConstants.MIN_POOL_SUPPLY;
    }
    function MAX_POOL_SUPPLY() public pure returns (uint) {
        return KassandraConstants.MAX_POOL_SUPPLY;
    }
    function EXIT_FEE() public pure returns (uint) {
        return KassandraConstants.EXIT_FEE;
    }
    function MIN_FEE() public pure returns (uint) {
        return KassandraConstants.MIN_FEE;
    }
    function MAX_FEE() public pure returns (uint) {
        return KassandraConstants.MAX_FEE;
    }
    function MAX_IN_RATIO() public pure returns (uint) {
        return KassandraConstants.MAX_IN_RATIO;
    }
    function MAX_OUT_RATIO() public pure returns (uint) {
        return KassandraConstants.MAX_OUT_RATIO;
    }
    function MIN_ASSET_LIMIT() public pure returns (uint) {
        return KassandraConstants.MIN_ASSET_LIMIT;
    }
    function MAX_ASSET_LIMIT() public pure returns (uint) {
        return KassandraConstants.MAX_ASSET_LIMIT;
    }
    function MAX_UINT() public pure returns (uint) {
        return KassandraConstants.MAX_UINT;
    }
    function MIN_CORE_BALANCE() public pure returns (uint) {
        return KassandraConstants.MIN_CORE_BALANCE;
    }
    function MIN_BPOW_BASE() public pure returns (uint) {
        return KassandraConstants.MIN_BPOW_BASE;
    }
    function MAX_BPOW_BASE() public pure returns (uint) {
        return KassandraConstants.MAX_BPOW_BASE;
    }
    function BPOW_PRECISION() public pure returns (uint) {
        return KassandraConstants.BPOW_PRECISION;
    }
}
