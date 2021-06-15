// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @author Kassandra (from Balancer Labs)
 * @title Put all the constants in one place
 */

library KassandraConstants {
    // State variables (must be constant in a library)

    // "ONE" - all math is in the "realm" of 10 ** 18;
    // where numeric 1 = 10 ** 18
    uint public constant ONE               = 10**18;

    uint public constant MIN_WEIGHT        = ONE;
    uint public constant MAX_WEIGHT        = ONE * 50;
    uint public constant MAX_TOTAL_WEIGHT  = ONE * 50;

    uint public constant MIN_BALANCE       = ONE / 10**6;
    uint public constant MAX_BALANCE       = ONE * 10**12;

    uint public constant MIN_POOL_SUPPLY   = ONE * 100;
    uint public constant MAX_POOL_SUPPLY   = ONE * 10**9;

    // EXIT_FEE must always be zero, or ConfigurableRightsPool._pushUnderlying will fail
    uint public constant EXIT_FEE          = 0;
    uint public constant MIN_FEE           = ONE / 10**6;
    uint public constant MAX_FEE           = ONE / 10;

    uint public constant MAX_IN_RATIO      = ONE / 2;
    uint public constant MAX_OUT_RATIO     = (ONE / 3) + 1 wei;

    uint public constant MIN_ASSET_LIMIT = 2;
    uint public constant MAX_ASSET_LIMIT = 8;

    uint public constant MAX_UINT = type(uint).max;

    // Core Pools
    uint public constant MIN_CORE_BALANCE  = ONE / 10**12;
    uint public constant INIT_POOL_SUPPLY  = ONE * 100;

    // Core Num
    uint public constant MIN_BPOW_BASE     = 1 wei;
    uint public constant MAX_BPOW_BASE     = (2 * ONE) - 1 wei;
    uint public constant BPOW_PRECISION    = ONE / 10**10;
}
