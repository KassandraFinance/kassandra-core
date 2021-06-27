// SPDX-License-Identifier: GPL3-or-later
pragma solidity ^0.8.0;

import "../../libraries/KassandraConstants.sol";

/*
 * @title Wrap KassandraConstant for tests
*/
contract KassandraConstantsMock {
    function one() external pure returns (uint) {
        return KassandraConstants.ONE;
    }

    function maxAssetLimit() external pure returns (uint) {
        return KassandraConstants.MAX_ASSET_LIMIT;
    }

    function exitFee() external pure returns (uint) {
        return KassandraConstants.EXIT_FEE;
    }
}
