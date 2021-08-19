// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ConfigurableRightsPool.sol";

import "./utils/Ownable.sol";

import "./interfaces/IcrpFactory.sol";

import { RightsManager } from "./libraries/RightsManager.sol";
import "./libraries/KassandraConstants.sol";

/**
 * @author Kassandra (and Balancer Labs)
 *
 * @title Configurable Rights Pool Factory - create parameterized smart pools
 *
 * @dev Rights are held in a corresponding struct in ConfigurableRightsPool
 *      Index values are as follows:
 *      0: canPauseSwapping - can setPublicSwap back to false after turning it on
 *                            by default, it is off on initialization and can only be turned on
 *      1: canChangeSwapFee - can setSwapFee after initialization (by default, it is fixed at create time)
 *      2: canChangeWeights - can bind new token weights (allowed by default in base pool)
 *      3: canAddRemoveTokens - can bind/unbind tokens (allowed by default in base pool)
 *      4: canWhitelistLPs - if set, only whitelisted addresses can join pools
 *                           (enables private pools with more than one LP)
 *      5: canChangeCap - can change the KSP cap (max # of pool tokens)
 */
contract CRPFactory is IcrpFactory, Ownable {
    // Keep a list of all Configurable Rights Pools
    mapping(address=>bool) private _isCrp;

    /**
     * @notice Log the address of each new smart pool, and its creator
     *
     * @param caller - Address that created the pool
     * @param pool - Address of the created pool
     */
    event LogNewCrp(
        address indexed caller,
        address indexed pool
    );

    /**
     * @notice Create a new CRP
     *
     * @dev emits a LogNewCRP event
     *
     * @param factoryAddress - the Factory instance used to create the underlying pool
     * @param poolParams - struct containing the names, tokens, weights, balances, and swap fee
     * @param rights - struct of permissions, configuring this CRP instance (see above for definitions)
     *
     * @return crp - ConfigurableRightPool instance of the created CRP
     */
    function newCrp(
        address factoryAddress,
        ConfigurableRightsPool.PoolParams calldata poolParams,
        RightsManager.Rights calldata rights
    )
        external onlyOwner
        returns (ConfigurableRightsPool crp)
    {
        require(poolParams.constituentTokens.length >= KassandraConstants.MIN_ASSET_LIMIT, "ERR_TOO_FEW_TOKENS");

        // Arrays must be parallel
        require(poolParams.tokenBalances.length == poolParams.constituentTokens.length, "ERR_START_BALANCES_MISMATCH");
        require(poolParams.tokenWeights.length == poolParams.constituentTokens.length, "ERR_START_WEIGHTS_MISMATCH");

        crp = new ConfigurableRightsPool(
            factoryAddress,
            poolParams,
            rights
        );

        emit LogNewCrp(msg.sender, address(crp));

        _isCrp[address(crp)] = true;
        // The caller is the controller of the CRP
        // The CRP will be the controller of the underlying Core Pool
        crp.setController(msg.sender);
    }

    /**
     * @notice Check to see if a given address is a CRP
     *
     * @param addr - Address to check
     *
     * @return boolean indicating whether it is a CRP
     */
    function isCrp(address addr)
        external view override
        returns (bool)
    {
        return _isCrp[addr];
    }
}
