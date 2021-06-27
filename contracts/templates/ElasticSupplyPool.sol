// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

// Imports

import "../../interfaces/IFactory.sol";
import "../PCToken.sol";
import "../utils/ReentrancyGuard.sol";
import "../utils/Ownable.sol";
import "../ConfigurableRightsPool.sol";

// Interfaces

// Libraries
import { RightsManager } from "../../libraries/RightsManager.sol";

// Contracts

/**
 * @author Ampleforth engineering team & Balancer Labs & Kassandra
 *
 * Reference:
 * https://github.com/balancer-labs/configurable-rights-pool/blob/master/contracts/templates/ElasticSupplyPool.sol
 *
 * @title Ampl Elastic Configurable Rights Pool.
 *
 * @dev   Extension of Kassandra configurable rights pool (smart-pool).
 *        Amples are a dynamic supply tokens, supply and individual balances change daily by a Rebase operation.
 *        In constant-function markets, Ampleforth's supply adjustments result in Impermanent Loss (IL)
 *        to liquidity providers. The AmplElasticCRP is an extension of Kassandra
 *        ConfigurableRightsPool which mitigates IL induced by supply adjustments.
 *
 *        It accomplishes this by doing the following mechanism:
 *        The `resyncWeight` method will be invoked atomically after rebase through Ampleforth's orchestrator.
 *
 *        When rebase changes supply, ampl weight is updated to the geometric mean of
 *        the current ampl weight and the target. Every other token's weight is updated
 *        proportionally such that relative ratios are same.
 *
 *        Weights: {w_ampl, w_t1 ... w_tn}
 *
 *        Rebase_change: x% (Ample's supply changes by x%, can be positive or negative)
 *
 *        Ample target weight: w_ampl_target = (100+x)/100 * w_ampl
 *
 *        w_ampl_new = sqrt(w_ampl * w_ampl_target)  // geometric mean
 *        for i in tn:
 *           w_ti_new = (w_ampl_new * w_ti) / w_ampl_target
 *
 */
contract ElasticSupplyPool is ConfigurableRightsPool {
    using KassandraSafeMath for uint;

    // Modifiers

    // Function declarations

    /**
     * @notice Construct a new Configurable Rights Pool (wrapper around core Pool)
     * @param factoryAddress - the core Pool Factory used to create the underlying pool
     * @param poolParams - CRP pool parameters
     * @param rightsParams - Set of permissions we are assigning to this smart pool
     */
    constructor(
        address factoryAddress,
        ConfigurableRightsPool.PoolParams memory poolParams,
        RightsManager.Rights memory rightsParams
    )
        ConfigurableRightsPool(factoryAddress, poolParams, rightsParams)
    {
        require(rightsParams.canChangeWeights, "ERR_NOT_CONFIGURABLE_WEIGHTS");
    }

    // External functions

    /**
     * @notice Update the weight of a token without changing the price (or transferring tokens)
     * @param token The address of the token in the underlying core Pool to be weight adjusted.
     * @dev Checks if the token's current pool balance has deviated from cached balance,
     *      if so it adjusts the token's weights proportional to the deviation.
     *      The underlying core Pool enforces bounds on MIN_WEIGHTS=1e18, MAX_WEIGHT=50e18 and TOTAL_WEIGHT=50e18.
     *      NOTE: The Pool.rebind function CAN REVERT if the updated weights go beyond the enforced bounds.
     */
    function resyncWeight(address token)
        external
        logs
        lock
        needsCorePool
        virtual
    {
        require(gradualUpdate.startBlock == 0, "ERR_NO_UPDATE_DURING_GRADUAL");
        require(IPool(address(corePool)).isBound(token), "ERR_NOT_BOUND");

        // get cached balance
        uint tokenBalanceBefore = IPool(address(corePool)).getBalance(token);

        // sync balance
        IPool(address(corePool)).gulp(token);

        // get new balance
        uint tokenBalanceAfter = IPool(address(corePool)).getBalance(token);

        // No-Op
        if(tokenBalanceBefore == tokenBalanceAfter) {
            return;
        }

        // current token weight
        uint tokenWeightBefore = IPool(address(corePool)).getDenormalizedWeight(token);

        // target token weight = RebaseRatio * previous token weight
        uint tokenWeightTarget = KassandraSafeMath.bdiv(
            KassandraSafeMath.bmul(tokenWeightBefore, tokenBalanceAfter),
            tokenBalanceBefore
        );

        // new token weight = sqrt(current token weight * target token weight)
        uint tokenWeightAfter = KassandraSafeMath.sqrt(
            KassandraSafeMath.bdiv(
                KassandraSafeMath.bmul(tokenWeightBefore, tokenWeightTarget), 1
            )
        );

        address[] memory tokens = IPool(address(corePool)).getCurrentTokens();
        for(uint i=0; i<tokens.length; i++){
            if(tokens[i] == token) {
                // adjust weight
                IPool(address(corePool)).rebind(token, tokenBalanceAfter, tokenWeightAfter);
            }
            else {
                uint otherWeightBefore = IPool(address(corePool)).getDenormalizedWeight(tokens[i]);
                uint otherBalance = corePool.getBalance(tokens[i]);

                // other token weight = (new token weight * other token weight before) / target token weight
                uint otherWeightAfter = KassandraSafeMath.bdiv(
                    KassandraSafeMath.bmul(tokenWeightAfter, otherWeightBefore), tokenWeightTarget
                );

                // adjust weight
                IPool(address(corePool)).rebind(tokens[i], otherBalance, otherWeightAfter);
            }
        }
    }
    
    /**
     * @notice ElasticSupply pools don't have updateWeightsGradually, so cannot call this
     * param initialSupply starting token balance
     * param minimumWeightChangeBlockPeriod - Enforce a minimum time between the start and end blocks
     * param addTokenTimeLockInBlocks - Enforce a mandatory wait time between updates
     *                                   This is also the wait time between committing and applying a new token
     */
    function createPool(
        uint, // initialSupply
        uint, // minimumWeightChangeBlockPeriod
        uint // addTokenTimeLockInBlocks
    )
        external
        pure
        override
    {
        revert("ERR_UNSUPPORTED_OPERATION");
    }

    /**
     * @notice Update the weight of an existing token - cannot do this in ElasticSupplyPools
     * param token - token to be reweighted
     * param newWeight - new weight of the token
    */
    function updateWeight(
        address, // token
        uint // newWeight
    )
        external
        pure
        override
    {
        revert("ERR_UNSUPPORTED_OPERATION");
    }

    /**
     * @notice Update weights in a predetermined way, between startBlock and endBlock,
     *         through external calls to pokeWeights -- cannot do this in ElasticSupplyPools
     * @dev Makes sure we aren't already in a weight update scheme
     *      Must call pokeWeights at least once past the end for it to do the final update
     *      and enable calling this again. (Could make this check for that case, but unwarranted complexity.)
     * param newWeights - final weights we want to get to
     * param startBlock - when weights should start to change
     * param endBlock - when weights will be at their final values
    */
    function updateWeightsGradually(
        uint[] calldata, // newWeights
        uint, // startBlock
        uint // endBlock
    )
        external
        pure
        override
    {
        revert("ERR_UNSUPPORTED_OPERATION");
    }

    /**
     * @notice External function called to make the contract update weights according to plan
     *         Unsupported in ElasticSupplyPools
    */
    function pokeWeights()
        external
        pure
        override
    {
        revert("ERR_UNSUPPORTED_OPERATION");
    }
}
