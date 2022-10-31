// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";

import "../libraries/KassandraConstants.sol";
import "../libraries/KassandraSafeMath.sol";
import "../libraries/SafeERC20.sol";

import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IKassandraCommunityStore.sol";
import "../interfaces/IPool.sol";

contract KassandraManualStrategy is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Maximum percentage a token must have in the pool for it to be removed or added
    uint public normalizedWeightForTokenManipulation;
    /// @notice Maximum percentage change that is allowed per block
    uint public maxWeigthChangePerBlock;
    /// @notice Storage contract that holds manager and pool information
    IKassandraCommunityStore public dataStore;

    /**
     * @notice Checks if the caller is the owner of the pool
     *
     * @param crpPoolAddress - pool that will be manipulated
     */
    modifier onlyPoolManager(address crpPoolAddress) {
        require(dataStore.getPoolInfo(crpPoolAddress).manager == msg.sender, "ERR_NOT_POOL_MANAGER");
        _;
    }

    /**
     * @notice Values can be edited later on
     *
     * @param store - Storage contract that holds manager and pool information
     * @param weightPerBlock - Maximum percentage a token must have in the pool for it to be removed or added
     * @param weightForToken - Maximum percentage change that is allowed per block
     */
    constructor (
        address store,
        uint weightPerBlock,
        uint weightForToken
    ) {
        require(weightForToken < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        require(weightPerBlock < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        require(store != address(0), "ERR_WRITER_ADDRESS_ZERO");
        normalizedWeightForTokenManipulation = weightForToken;
        maxWeigthChangePerBlock = weightPerBlock;
        dataStore = IKassandraCommunityStore(store);
    }

    /**
     * @notice Change the maximum percentage a token must have in the pool for it to be removed or added.
     *
     * @param percent - maximum normalized weight
     */
    function setNormalizedWeightForTokenManipulation(uint percent)
        external
        onlyOwner
    {
        require(percent < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        normalizedWeightForTokenManipulation = percent;
    }

    /**
     * @notice Change the maximum percentage change that is allowed per block
     *
     * @param weightPerBlock - new normalized weight (percentage)
     */
    function setMaxWeigthChangePerBlock(uint weightPerBlock)
        external
        onlyOwner
    {
        require(weightPerBlock < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        maxWeigthChangePerBlock = weightPerBlock;
    }

    /**
     * @notice Change the storage contract that holds manager and pool information
     *
     * @param contractAddr - new storage contract
     */
    function setDataStore(address contractAddr)
        external
        onlyOwner
    {
        require(contractAddr != address(0), "ERR_WRITER_ADDRESS_ZERO");
        dataStore = IKassandraCommunityStore(contractAddr);
    }

    /**
     * @notice Schedule (commit) a token to be added; must call applyAddToken after a fixed
     *         number of blocks to actually add the token
     *
     * @dev Wraps the crpPool function to prevent the strategy updating weights while adding
     *      a token and to also update the strategy with the new token. Tokens for filling the
     *      balance should be sent to this contract so that applying the token can happen.
     *
     * @param crpPoolAddress - CRP to manipulate
     * @param token - Address of the token to be added
     * @param balance - How much to be added
     * @param denormalizedWeight - The desired token weight
     */
    function commitAddToken(
        address crpPoolAddress,
        address token,
        uint balance,
        uint denormalizedWeight
        )
        external
        onlyPoolManager(crpPoolAddress)
    {
        require(dataStore.isTokenWhitelisted(token), "ERR_TOKEN_NOT_WHITELISTED");
        IConfigurableRightsPool crpPool = IConfigurableRightsPool(crpPoolAddress);
        IPool corePool = crpPool.corePool();
        uint normalizedWeight = KassandraSafeMath.bdiv(
            denormalizedWeight,
            corePool.getTotalDenormalizedWeight() + denormalizedWeight
        );
        require(normalizedWeight <= normalizedWeightForTokenManipulation, "ERR_WEIGHT_TOO_HIGH");
        IERC20(token).safeApprove(crpPoolAddress, balance);
        crpPool.commitAddToken(token, balance, denormalizedWeight);
    }

    /**
     * @notice Add the token previously committed (in commitAddToken) to the pool
     *         The governance must have the tokens in its wallet, it will also receive the extra pool shares
     *
     * @dev This will apply adding the token, anyone can call it so that the governance doesn't need to
     *      create two proposals to do the same thing. Adding the token has already been accepted.
     *
     *      This will also allow calling API3 again
     *
     *      applyAddToken on crpPool locks
     *
     * @param crpPoolAddress - CRP to manipulate
     */
    function applyAddToken(address crpPoolAddress)
        external
        onlyPoolManager(crpPoolAddress)
    {
        IConfigurableRightsPool crpPool = IConfigurableRightsPool(crpPoolAddress);
        (, address token, , , uint balance) = crpPool.newToken();
        IERC20(token).transferFrom(msg.sender, address(this), balance);
        crpPool.applyAddToken();
    }

    /**
     * @notice Remove a token from the pool
     *
     * @dev crpPoolAddress is a contract interface; function calls on it are external
     *
     * @param crpPoolAddress - CRP to manipulate
     * @param token - token to remove
     */
    function removeToken(
        address crpPoolAddress,
        address token
        )
        external
        onlyPoolManager(crpPoolAddress)
    {
        IConfigurableRightsPool crpPool = IConfigurableRightsPool(crpPoolAddress);
        IPool corePool = crpPool.corePool();
        uint normalizedWeight = corePool.getNormalizedWeight(token);
        require(normalizedWeight <= normalizedWeightForTokenManipulation, "ERR_WEIGHT_TOO_HIGH");
        crpPool.removeToken(token);
        IERC20(token).safeTransfer(msg.sender, corePool.getBalance(token));
    }

    /**
     * @notice Calculates the allocations and updates the weights in the pool
     *         Anyone can call this, but only once
     *         The strategy may pause itself if the allocations go beyond what's expected
     *
     * @param crpPoolAddress - CRP to manipulate
     */
    function updateWeightsGradually(
        address crpPoolAddress,
        uint[] calldata newWeights,
        uint startBlock,
        uint endBlock
        )
        external
        onlyPoolManager(crpPoolAddress)
    {
        IConfigurableRightsPool crpPool = IConfigurableRightsPool(crpPoolAddress);
        IPool corePool = crpPool.corePool();
        uint totalWeight = 0;
        uint blocksDiff = endBlock - startBlock;
        address[] memory tokens = corePool.getCurrentTokens();

        for (uint i = newWeights.length; i > 0;) {
            totalWeight += newWeights[--i];
        }

        for (uint i = newWeights.length; i > 0;) {
            uint newNormalizedWeight = KassandraSafeMath.bdiv(newWeights[--i], totalWeight);
            uint oldNormalizedWeight = corePool.getNormalizedWeight(tokens[i]);
            uint weightDiff;

            if (oldNormalizedWeight > newNormalizedWeight) {
                weightDiff = oldNormalizedWeight - newNormalizedWeight;
            } else {
                weightDiff = newNormalizedWeight - oldNormalizedWeight;
            }

            require(KassandraSafeMath.bdiv(weightDiff, blocksDiff) < maxWeigthChangePerBlock, "ERR_WEIGHT_CHANGE_SPEED");
        }

        crpPool.updateWeightsGradually(newWeights, startBlock, endBlock);
    }
}
