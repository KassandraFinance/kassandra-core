// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../libraries/BalancerConstants.sol";
import "../../libraries/BalancerSafeMath.sol";

abstract contract Math {
    using KassandraSafeMath for uint;

    /**********************************************************************************************
    // calcSpotPrice                                                                             //
    // sP = spotPrice                                                                            //
    // bI = tokenBalanceIn                ( bI / wI )         1                                  //
    // bO = tokenBalanceOut         sP =  -----------  *  ----------                             //
    // wI = tokenWeightIn                 ( bO / wO )     ( 1 - sF )                             //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcSpotPrice(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint swapFee
    )
        public pure
        returns (uint spotPrice)
    {
        uint numer = KassandraSafeMath.bdiv(tokenBalanceIn, tokenWeightIn);
        uint denom = KassandraSafeMath.bdiv(tokenBalanceOut, tokenWeightOut);
        uint ratio = KassandraSafeMath.bdiv(numer, denom);
        uint scale = KassandraSafeMath.bdiv(KassandraConstants.ONE, (KassandraConstants.ONE - swapFee));
        return (spotPrice = KassandraSafeMath.bmul(ratio, scale));
    }

    /**********************************************************************************************
    // calcOutGivenIn                                                                            //
    // aO = tokenAmountOut                                                                       //
    // bO = tokenBalanceOut                                                                      //
    // bI = tokenBalanceIn              /      /            bI             \    (wI / wO) \      //
    // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  | ^            |     //
    // wI = tokenWeightIn               \      \ ( bI + ( aI * ( 1 - sF )) /              /      //
    // wO = tokenWeightOut                                                                       //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcOutGivenIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountIn,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountOut)
    {
        uint weightRatio = KassandraSafeMath.bdiv(tokenWeightIn, tokenWeightOut);
        uint adjustedIn = KassandraConstants.ONE - swapFee;
        adjustedIn = KassandraSafeMath.bmul(tokenAmountIn, adjustedIn);
        uint y = KassandraSafeMath.bdiv(tokenBalanceIn, (tokenBalanceIn + adjustedIn));
        uint foo = KassandraSafeMath.bpow(y, weightRatio);
        uint bar = KassandraConstants.ONE - foo;
        tokenAmountOut = KassandraSafeMath.bmul(tokenBalanceOut, bar);
        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcInGivenOut                                                                            //
    // aI = tokenAmountIn                                                                        //
    // bO = tokenBalanceOut               /  /     bO      \    (wO / wI)      \                 //
    // bI = tokenBalanceIn          bI * |  | ------------  | ^            - 1  |                //
    // aO = tokenAmountOut    aI =        \  \ ( bO - aO ) /                   /                 //
    // wI = tokenWeightIn           --------------------------------------------                 //
    // wO = tokenWeightOut                          ( 1 - sF )                                   //
    // sF = swapFee                                                                              //
    **********************************************************************************************/
    function calcInGivenOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint tokenAmountOut,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountIn)
    {
        uint weightRatio = KassandraSafeMath.bdiv(tokenWeightOut, tokenWeightIn);
        uint diff = tokenBalanceOut - tokenAmountOut;
        uint y = KassandraSafeMath.bdiv(tokenBalanceOut, diff);
        uint foo = KassandraSafeMath.bpow(y, weightRatio);
        foo = foo - KassandraConstants.ONE;
        tokenAmountIn = KassandraConstants.ONE - swapFee;
        tokenAmountIn = KassandraSafeMath.bdiv(KassandraSafeMath.bmul(tokenBalanceIn, foo), tokenAmountIn);
        return tokenAmountIn;
    }

    /**********************************************************************************************
    // calcPoolOutGivenSingleIn                                                                  //
    // pAo = poolAmountOut         /                                              \              //
    // tAi = tokenAmountIn        ///      /     //    wI \      \\       \     wI \             //
    // wI = tokenWeightIn        //| tAi *| 1 - || 1 - --  | * sF || + tBi \    --  \            //
    // tW = totalWeight     pAo=||  \      \     \\    tW /      //         | ^ tW   | * pS - pS //
    // tBi = tokenBalanceIn      \\  ------------------------------------- /        /            //
    // pS = poolSupply            \\                    tBi               /        /             //
    // sF = swapFee                \                                              /              //
    **********************************************************************************************/
    function calcPoolOutGivenSingleIn(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountIn,
        uint swapFee
    )
        public pure
        returns (uint poolAmountOut)
    {
        // Charge the trading fee for the proportion of tokenAi
        //   which is implicitly traded to the other pool tokens.
        // That proportion is (1- weightTokenIn)
        // tokenAiAfterFee = tAi * (1 - (1-weightTi) * poolFee);
        uint normalizedWeight = KassandraSafeMath.bdiv(tokenWeightIn, totalWeight);
        uint zaz = KassandraSafeMath.bmul((KassandraConstants.ONE - normalizedWeight), swapFee);
        uint tokenAmountInAfterFee = KassandraSafeMath.bmul(tokenAmountIn, (KassandraConstants.ONE - zaz));

        uint newTokenBalanceIn = tokenBalanceIn + tokenAmountInAfterFee;
        uint tokenInRatio = KassandraSafeMath.bdiv(newTokenBalanceIn, tokenBalanceIn);

        // uint newPoolSupply = (ratioTi ^ weightTi) * poolSupply;
        uint poolRatio = KassandraSafeMath.bpow(tokenInRatio, normalizedWeight);
        uint newPoolSupply = KassandraSafeMath.bmul(poolRatio, poolSupply);
        poolAmountOut = newPoolSupply - poolSupply;
        return poolAmountOut;
    }

    /**********************************************************************************************
    // calcSingleInGivenPoolOut                                                                  //
    // tAi = tokenAmountIn              //(pS + pAo)\     /    1    \\                           //
    // pS = poolSupply                 || ---------  | ^ | --------- || * bI - bI                //
    // pAo = poolAmountOut              \\    pS    /     \(wI / tW)//                           //
    // bI = balanceIn          tAi =  --------------------------------------------               //
    // wI = weightIn                              /      wI  \                                   //
    // tW = totalWeight                          |  1 - ----  |  * sF                            //
    // sF = swapFee                               \      tW  /                                   //
    **********************************************************************************************/
    function calcSingleInGivenPoolOut(
        uint tokenBalanceIn,
        uint tokenWeightIn,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountOut,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountIn)
    {
        uint normalizedWeight = KassandraSafeMath.bdiv(tokenWeightIn, totalWeight);
        uint newPoolSupply = poolSupply + poolAmountOut;
        uint poolRatio = KassandraSafeMath.bdiv(newPoolSupply, poolSupply);

        //uint newBalTi = poolRatio^(1/weightTi) * balTi;
        uint boo = KassandraSafeMath.bdiv(KassandraConstants.ONE, normalizedWeight);
        uint tokenInRatio = KassandraSafeMath.bpow(poolRatio, boo);
        uint newTokenBalanceIn = KassandraSafeMath.bmul(tokenInRatio, tokenBalanceIn);
        uint tokenAmountInAfterFee = newTokenBalanceIn - tokenBalanceIn;
        // Do reverse order of fees charged in joinswap_ExternAmountIn, this way
        //     ``` pAo == joinswap_ExternAmountIn(Ti, joinswap_PoolAmountOut(pAo, Ti)) ```
        //uint tAi = tAiAfterFee / (1 - (1-weightTi) * swapFee) ;
        uint zar = KassandraSafeMath.bmul((KassandraConstants.ONE - normalizedWeight), swapFee);
        tokenAmountIn = KassandraSafeMath.bdiv(tokenAmountInAfterFee, (KassandraConstants.ONE - zar));
        return tokenAmountIn;
    }

    /**********************************************************************************************
    // calcSingleOutGivenPoolIn                                                                  //
    // tAo = tokenAmountOut            /      /                                             \\   //
    // bO = tokenBalanceOut           /      // pS - (pAi * (1 - eF)) \     /    1    \      \\  //
    // pAi = poolAmountIn            | bO - || ----------------------- | ^ | --------- | * b0 || //
    // ps = poolSupply                \      \\          pS           /     \(wO / tW)/      //  //
    // wI = tokenWeightIn      tAo =   \      \                                             //   //
    // tW = totalWeight                    /     /      wO \       \                             //
    // sF = swapFee                    *  | 1 - |  1 - ---- | * sF  |                            //
    // eF = exitFee                        \     \      tW /       /                             //
    **********************************************************************************************/
    function calcSingleOutGivenPoolIn(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint poolAmountIn,
        uint swapFee
    )
        public pure
        returns (uint tokenAmountOut)
    {
        uint normalizedWeight = KassandraSafeMath.bdiv(tokenWeightOut, totalWeight);
        // charge exit fee on the pool token side
        // pAiAfterExitFee = pAi*(1-exitFee)
        uint poolAmountInAfterExitFee = KassandraSafeMath.bmul(poolAmountIn, (KassandraConstants.ONE - KassandraConstants.EXIT_FEE));
        uint newPoolSupply = poolSupply - poolAmountInAfterExitFee;
        uint poolRatio = KassandraSafeMath.bdiv(newPoolSupply, poolSupply);

        // newBalTo = poolRatio^(1/weightTo) * balTo;
        uint tokenOutRatio = KassandraSafeMath.bpow(poolRatio, KassandraSafeMath.bdiv(KassandraConstants.ONE, normalizedWeight));
        uint newTokenBalanceOut = KassandraSafeMath.bmul(tokenOutRatio, tokenBalanceOut);

        uint tokenAmountOutBeforeSwapFee = tokenBalanceOut - newTokenBalanceOut;

        // charge swap fee on the output token side
        //uint tAo = tAoBeforeSwapFee * (1 - (1-weightTo) * swapFee)
        uint zaz = KassandraSafeMath.bmul((KassandraConstants.ONE - normalizedWeight), swapFee);
        tokenAmountOut = KassandraSafeMath.bmul(tokenAmountOutBeforeSwapFee, (KassandraConstants.ONE - zaz));
        return tokenAmountOut;
    }

    /**********************************************************************************************
    // calcPoolInGivenSingleOut                                                                  //
    // pAi = poolAmountIn               // /               tAo             \\     / wO \     \   //
    // bO = tokenBalanceOut            // | bO - -------------------------- |\   | ---- |     \  //
    // tAo = tokenAmountOut      pS - ||   \     1 - ((1 - (tO / tW)) * sF)/  | ^ \ tW /  * pS | //
    // ps = poolSupply                 \\ -----------------------------------/                /  //
    // wO = tokenWeightOut  pAi =       \\               bO                 /                /   //
    // tW = totalWeight           -------------------------------------------------------------  //
    // sF = swapFee                                        ( 1 - eF )                            //
    // eF = exitFee                                                                              //
    **********************************************************************************************/
    function calcPoolInGivenSingleOut(
        uint tokenBalanceOut,
        uint tokenWeightOut,
        uint poolSupply,
        uint totalWeight,
        uint tokenAmountOut,
        uint swapFee
    )
        public pure
        returns (uint poolAmountIn)
    {

        // charge swap fee on the output token side
        uint normalizedWeight = KassandraSafeMath.bdiv(tokenWeightOut, totalWeight);
        //uint tAoBeforeSwapFee = tAo / (1 - (1-weightTo) * swapFee) ;
        uint zoo = KassandraConstants.ONE - normalizedWeight;
        uint zar = KassandraSafeMath.bmul(zoo, swapFee);
        uint tokenAmountOutBeforeSwapFee = KassandraSafeMath.bdiv(tokenAmountOut, (KassandraConstants.ONE - zar));

        uint newTokenBalanceOut = tokenBalanceOut - tokenAmountOutBeforeSwapFee;
        uint tokenOutRatio = KassandraSafeMath.bdiv(newTokenBalanceOut, tokenBalanceOut);

        //uint newPoolSupply = (ratioTo ^ weightTo) * poolSupply;
        uint poolRatio = KassandraSafeMath.bpow(tokenOutRatio, normalizedWeight);
        uint newPoolSupply = KassandraSafeMath.bmul(poolRatio, poolSupply);
        uint poolAmountInAfterExitFee = poolSupply - newPoolSupply;

        // charge exit fee on the pool token side
        // pAi = pAiAfterExitFee/(1-exitFee)
        poolAmountIn = KassandraSafeMath.bdiv(poolAmountInAfterExitFee, (KassandraConstants.ONE - KassandraConstants.EXIT_FEE));
        return poolAmountIn;
    }


}
