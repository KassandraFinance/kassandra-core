// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../libraries/KassandraSafeMath.sol";

//  This test is similar to TPoolJoin but with an exit fee
contract TPoolJoinExit {
    using KassandraSafeMath for uint;

    bool public echidna_no_bug_found = true;

    // joinPool models the Pool.joinPool behavior for one token
    function joinPool(uint poolAmountOut, uint poolTotal, uint _records_t_balance)
        internal pure returns(uint)
    {
        uint ratio = KassandraSafeMath.bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        uint bal = _records_t_balance;
        uint tokenAmountIn = KassandraSafeMath.bmul(ratio, bal);

        return tokenAmountIn;
    }

    // exitPool models the Pool.exitPool behavior for one token
    function exitPool(uint poolAmountIn, uint poolTotal, uint _records_t_balance)
        internal pure returns(uint)
    {
        uint exitFee = KassandraSafeMath.bmul(poolAmountIn, KassandraConstants.EXIT_FEE);
        uint pAiAfterExitFee = poolAmountIn - exitFee;
        uint ratio = KassandraSafeMath.bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        uint bal = _records_t_balance;
        uint tokenAmountOut = KassandraSafeMath.bmul(ratio, bal);

        return tokenAmountOut;
    }


    // This function model an attacker calling joinPool - exitPool and taking advantage of potential rounding
    // issues to generate free pool token
    function joinAndExitPool(uint poolAmountOut, uint poolAmountIn, uint poolTotal, uint _records_t_balance) public {
        uint tokenAmountIn = joinPool(poolAmountOut, poolTotal, _records_t_balance);

        // We constraint poolTotal and _records_t_balance
        // To have "realistic" values
        require(poolTotal <= 100 ether);
        require(poolTotal >= 1 ether);
        require(_records_t_balance <= 10 ether);
        require(_records_t_balance >= 10**6);

        poolTotal += poolAmountOut;
        _records_t_balance += tokenAmountIn;

        require(tokenAmountIn > 0); // prevent triggering the free token generation from joinPool

        require(poolTotal >= poolAmountIn);
        uint tokenAmountOut = exitPool(poolAmountIn, poolTotal, _records_t_balance);
        require(_records_t_balance >= tokenAmountOut);

        // We try to generate free pool share
        require(poolAmountOut > poolAmountIn);
        require(tokenAmountOut == tokenAmountIn);
        echidna_no_bug_found = false;
    }

}