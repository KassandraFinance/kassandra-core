// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./Token.sol";

import "./utils/Ownable.sol";
import "./utils/ReentrancyGuard.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";

import { RightsManager } from "../libraries/RightsManager.sol";
import "../libraries/KassandraConstants.sol";
import "../libraries/SafeApprove.sol";
import "../libraries/SmartPoolManager.sol";

/**
 * @author Kassandra (and Balancer Labs)
 *
 * @title Smart Pool with customizable features
 *
 * @notice SPToken is the "Kassandra Smart Pool" token (transferred upon finalization)
 *
 * @dev Rights are defined as follows (index values into the array)
 *      0: canPauseSwapping - can setPublicSwap back to false after turning it on
 *                            by default, it is off on initialization and can only be turned on
 *      1: canChangeSwapFee - can setSwapFee after initialization (by default, it is fixed at create time)
 *      2: canChangeWeights - can bind new token weights (allowed by default in base pool)
 *      3: canAddRemoveTokens - can bind/unbind tokens (allowed by default in base pool)
 *      4: canWhitelistLPs - can restrict LPs to a whitelist
 *      5: canChangeCap - can change the KSP cap (max # of pool tokens)
 *
 * Note that functions called on corePool and coreFactory may look like internal calls,
 *   but since they are contracts accessed through an interface, they are really external.
 * To make this explicit, we could write "IPool(address(corePool)).function()" everywhere,
 *   instead of "corePool.function()".
 */
contract ConfigurableRightsPool is IConfigurableRightsPoolDef, SPToken, Ownable, ReentrancyGuard {
    using SafeApprove for IERC20;

    // struct used on pool creation
    struct PoolParams {
        // Kassandra Pool Token (representing shares of the pool)
        string poolTokenSymbol; // symbol of the pool token
        string poolTokenName;   // name of the pool token
        // Tokens inside the Pool
        address[] constituentTokens; // addresses
        uint[] tokenBalances;        // balances
        uint[] tokenWeights;         // denormalized weights
        // pool swap fee
        uint swapFee;
    }

    /// Address of the contract that handles the strategy
    address public strategyUpdater;

    /// Address of the core factory contract; for creating the core pool and enforcing $KACY
    IFactory public coreFactory;
    /// Address of the core pool for this CRP; holds the tokens
    IPool public override corePool;

    /// Struct holding the rights configuration
    RightsManager.Rights public rights;

    /// Hold the parameters used in updateWeightsGradually
    SmartPoolManager.GradualUpdateParams public gradualUpdate;

    /**
     * @notice This is for adding a new (currently unbound) token to the pool
     *         It's a two-step process: commitAddToken(), then applyAddToken()
     */
    SmartPoolManager.NewTokenParams public newToken;

    // Fee is initialized on creation, and can be changed if permission is set
    // Only needed for temporary storage between construction and createPool
    // Thereafter, the swap fee should always be read from the underlying pool
    uint private _initialSwapFee;

    // Store the list of tokens in the pool, and balances
    // NOTE that the token list is *only* used to store the pool tokens between
    //   construction and createPool - thereafter, use the underlying core Pool's list
    //   (avoids synchronization issues)
    address[] private _initialTokens;
    uint[] private _initialBalances;

    /// Enforce a minimum time between the start and end blocks on updateWeightsGradually
    uint public minimumWeightChangeBlockPeriod;
    /// Enforce a wait time between committing and applying a new token
    uint public addTokenTimeLockInBlocks;

    // Default values for the above variables, set in the constructor
    // Pools without permission to update weights or add tokens cannot use them anyway,
    //   and should call the default createPool() function.
    // To override these defaults, pass them into the overloaded createPool()
    // Period is in blocks; 500 blocks ~ 2 hours; 5,700 blocks ~< 1 day
    uint private constant _DEFAULT_MIN_WEIGHT_CHANGE_BLOCK_PERIOD = 5700;
    uint private constant _DEFAULT_ADD_TOKEN_TIME_LOCK_IN_BLOCKS = 500;

    /**
     * @notice Cap on the pool size (i.e., # of tokens minted when joining)
     *         Limits the risk of experimental pools; failsafe/backup for fixed-size pools
     */
    uint public tokenCap;

    // Whitelist of LPs (if configured)
    mapping(address => bool) private _liquidityProviderWhitelist;

    /**
     * @notice Emitted when the maximum cap (`tokenCap`) has changed
     *
     * @param caller - Address of who changed the cap
     * @param oldCap - Previous maximum cap
     * @param newCap - New maximum cap
     */
    event CapChanged(
        address indexed caller,
        uint oldCap,
        uint newCap
    );

    /**
     * @notice Emitted when a new token has been committed to be added to the pool
     *         The token has not been added yet, but eventually will be once pass `addTokenTimeLockInBlocks`
     *
     * param token - Address of the token being added
     * param pool - Address of the CRP pool that will have the new token
     * param caller - Address of who committed this new token
     */ 
    event NewTokenCommitted(
        address indexed token,
        address indexed pool,
        address indexed caller
    );

    /**
     * @notice Emitted when the strategy contract has been changed
     *
     * @param newAddr - Address of the new strategy contract
     * @param pool - Address of the CRP pool that changed the strategy contract
     * @param caller - Address of who changed the strategy contract
     */
    event NewStrategy(
        address indexed newAddr,
        address indexed pool,
        address indexed caller
    );

    /**
     * @notice Emitted on virtually every externally callable function
     *
     * @dev Anonymous logger event - can only be filtered by contract address
     *
     * @param sig - Function identifier
     * @param caller - Caller of the function
     * @param data - The full data of the call
     */
    event LogCall(
        bytes4  indexed sig,
        address indexed caller,
        bytes data
    ) anonymous;

    /**
     * @notice Emitted when someone joins the pool
     *         Also known as "Minted the pool token"
     *
     * @param caller - Adddress of who joined the pool
     * @param tokenIn - Address of the token that was sent to the pool
     * @param tokenAmountIn - Amount of the token added to the pool
     */
    event LogJoin(
        address indexed caller,
        address indexed tokenIn,
        uint tokenAmountIn
    );

    /**
     * @notice Emitted when someone exits the pool
     *         Also known as "Burned the pool token"
     *
     * @param caller - Adddress of who exited the pool
     * @param tokenOut - Address of the token that was sent to the caller
     * @param tokenAmountOut - Amount of the token sent to the caller
     */
    event LogExit(
        address indexed caller,
        address indexed tokenOut,
        uint tokenAmountOut
    );

    /**
     * @dev Logs a call to a function, only needed for external and public function
     */
    modifier logs() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /**
     * @dev Mark functions that require delegation to the underlying Pool
     */
    modifier needsCorePool() {
        require(address(corePool) != address(0), "ERR_NOT_CREATED");
        _;
    }

    /**
     * @dev Turn off swapping on the underlying pool during joins
     *      Otherwise tokens with callbacks would enable attacks involving simultaneous swaps and joins
     */
    modifier lockUnderlyingPool() {
        bool origSwapState = corePool.isPublicSwap();
        corePool.setPublicSwap(false);
        _;
        corePool.setPublicSwap(origSwapState);
    }

    /**
     * @dev Mark functions that only the strategy contract can control
     */
    modifier onlyStrategy() {
        require(msg.sender == strategyUpdater, "ERR_NOT_STRATEGY");
        _;
    }

    /**
     * @notice Construct a new Configurable Rights Pool (wrapper around core Pool)
     *
     * @dev _initialTokens and _swapFee are only used for temporary storage between construction
     *      and create pool, and should not be used thereafter! _initialTokens is destroyed in
     *      createPool to prevent this, and _swapFee is kept in sync (defensively), but
     *      should never be used except in this constructor and createPool()
     *
     * @param factoryAddress - Core Pool Factory used to create the underlying pool
     * @param poolParams - Struct containing pool parameters
     * @param rightsStruct - Set of permissions we are assigning to this smart pool
     */
    constructor(
        address factoryAddress,
        PoolParams memory poolParams,
        RightsManager.Rights memory rightsStruct
    )
        SPToken(poolParams.poolTokenSymbol, poolParams.poolTokenName)
    {
        // We don't have a pool yet; check now or it will fail later (in order of likelihood to fail)
        // (and be unrecoverable if they don't have permission set to change it)
        // Most likely to fail, so check first
        require(poolParams.swapFee >= KassandraConstants.MIN_FEE, "ERR_INVALID_SWAP_FEE");
        require(poolParams.swapFee <= KassandraConstants.MAX_FEE, "ERR_INVALID_SWAP_FEE");

        // Arrays must be parallel
        require(poolParams.tokenBalances.length == poolParams.constituentTokens.length, "ERR_START_BALANCES_MISMATCH");
        require(poolParams.tokenWeights.length == poolParams.constituentTokens.length, "ERR_START_WEIGHTS_MISMATCH");
        // Cannot have too many or too few - technically redundant, since Pool.bind() would fail later
        // But if we don't check now, we could have a useless contract with no way to create a pool

        require(poolParams.constituentTokens.length >= KassandraConstants.MIN_ASSET_LIMIT, "ERR_TOO_FEW_TOKENS");
        require(poolParams.constituentTokens.length <= KassandraConstants.MAX_ASSET_LIMIT, "ERR_TOO_MANY_TOKENS");
        // There are further possible checks (e.g., if they use the same token twice), but
        // we can let bind() catch things like that (i.e., not things that might reasonably work)

        coreFactory = IFactory(factoryAddress);

        SmartPoolManager.verifyTokenCompliance(
            poolParams.constituentTokens,
            poolParams.tokenWeights,
            coreFactory.minimumKacy(),
            coreFactory.kacyToken()
        );

        rights = rightsStruct;
        _initialTokens = poolParams.constituentTokens;
        _initialBalances = poolParams.tokenBalances;
        _initialSwapFee = poolParams.swapFee;

        // These default block time parameters can be overridden in createPool
        minimumWeightChangeBlockPeriod = _DEFAULT_MIN_WEIGHT_CHANGE_BLOCK_PERIOD;
        addTokenTimeLockInBlocks = _DEFAULT_ADD_TOKEN_TIME_LOCK_IN_BLOCKS;

        gradualUpdate.startWeights = poolParams.tokenWeights;
        // Initializing (unnecessarily) for documentation - 0 means no gradual weight change has been initiated
        gradualUpdate.startBlock = 0;
        // By default, there is no cap (unlimited pool token minting)
        tokenCap = KassandraConstants.MAX_UINT;
    }

    /**
     * @notice Set the swap fee on the underlying pool
     *
     * @dev Keep the local version and core in sync (see below)
     *      corePool is a contract interface; function calls on it are external
     *
     * @param swapFee - in Wei
     */
    function setSwapFee(uint swapFee)
        external
        lock
        logs
        onlyOwner
        needsCorePool
        virtual
    {
        require(rights.canChangeSwapFee, "ERR_NOT_CONFIGURABLE_SWAP_FEE");

        // Underlying pool will check against min/max fee
        corePool.setSwapFee(swapFee);
    }

    /**
     * @notice Set the cap (max # of pool tokens)
     *
     * @dev tokenCap defaults in the constructor to unlimited
     *      Can set to 0 (or anywhere below the current supply), to halt new investment
     *      Prevent setting it before creating a pool, since createPool sets to intialSupply
     *      (it does this to avoid an unlimited cap window between construction and createPool)
     *      Therefore setting it before then has no effect, so should not be allowed
     *
     * @param newCap - New value of the cap
     */
    function setCap(uint newCap)
        external
        lock
        logs
        onlyOwner
        needsCorePool
    {
        require(rights.canChangeCap, "ERR_CANNOT_CHANGE_CAP");

        emit CapChanged(msg.sender, tokenCap, newCap);

        tokenCap = newCap;
    }

    /**
     * @notice Set the public swap flag on the underlying pool to allow or prevent swapping in the pool
     *
     * @dev If this smart pool has canPauseSwapping enabled, we can turn publicSwap off if it's already on
     *      Note that if they turn swapping off - but then finalize the pool - finalizing will turn the
     *      swapping back on. They're not supposed to finalize the underlying pool... would defeat the
     *      smart pool functions. (Only the owner can finalize the pool - which is this contract -
     *      so there is no risk from outside.)
     *
     *      corePool is a contract interface; function calls on it are external
     *
     * @param publicSwap - New value of the swap status
     */
    function setPublicSwap(bool publicSwap)
        external
        lock
        logs
        onlyOwner
        needsCorePool
        virtual
    {
        require(rights.canPauseSwapping, "ERR_NOT_PAUSABLE_SWAP");

        corePool.setPublicSwap(publicSwap);
    }

    /**
     * @notice Set a contract/address that will be allowed to update weights and add/remove tokens
     *
     * @dev If this smart pool has canUpdateWeigths enabled, another smart contract with defined
     *      rules and formulas could update them
     *
     * @param updaterAddr - Contract address that will be able to update weights
     */
    function setStrategist(address updaterAddr)
        external
        logs
        onlyOwner
    {
        require(updaterAddr != address(0), "ERR_ZERO_ADDRESS");
        emit NewStrategy(updaterAddr, address(this), msg.sender);
        strategyUpdater = updaterAddr;
    }

    /**
     * @notice Create a new Smart Pool - and set the block period time parameters
     *
     * @dev Initialize the swap fee to the value provided in the CRP constructor
     *      Can be changed if the canChangeSwapFee permission is enabled
     *      Time parameters will be fixed at these values
     *      Delegates to internal function
     *
     *      If this contract doesn't have canChangeWeights permission - or you want to use the default
     *      values, the block time arguments are not needed, and you can just call the single-argument
     *      createPool()
     *
     * @param initialSupply - Starting token balance
     * @param minimumWeightChangeBlockPeriodParam - Enforce a minimum time between the start and end blocks
     * @param addTokenTimeLockInBlocksParam - Enforce a mandatory wait time between committing and applying a new token
     */
    function createPool(
        uint initialSupply,
        uint minimumWeightChangeBlockPeriodParam,
        uint addTokenTimeLockInBlocksParam
    )
        external
        lock
        logs
        onlyOwner
        virtual
    {
        require(
            minimumWeightChangeBlockPeriodParam >= addTokenTimeLockInBlocksParam,
            "ERR_INCONSISTENT_TOKEN_TIME_LOCK"
        );

        minimumWeightChangeBlockPeriod = minimumWeightChangeBlockPeriodParam;
        addTokenTimeLockInBlocks = addTokenTimeLockInBlocksParam;

        createPoolInternal(initialSupply);
    }

    /**
     * @notice Create a new Smart Pool
     *
     * @dev Initialize the swap fee to the value provided in the CRP constructor
     *      Can be changed if the canChangeSwapFee permission is enabled
     *      Delegates to internal function
     *
     * @param initialSupply - Starting token balance
     */
    function createPool(uint initialSupply)
        external
        lock
        logs
        onlyOwner
        virtual
    {
        createPoolInternal(initialSupply);
    }

    /**
     * @notice Update the weight of an existing token
     *
     * @dev Notice Balance is not an input (like with rebind on core Pool) since we will require prices not to change
     *      This is achieved by forcing balances to change proportionally to weights, so that prices don't change
     *      If prices could be changed, this would allow the controller to drain the pool by arbing price changes
     *
     * @param token - Address of the token to be reweighted
     * @param newWeight - New weight of the token
     */
    function updateWeight(address token, uint newWeight)
        external
        override
        lock
        logs
        needsCorePool
        onlyStrategy
        virtual
    {
        require(rights.canChangeWeights, "ERR_NOT_CONFIGURABLE_WEIGHTS");

        // We don't want people to set weights manually if there's a block-based update in progress
        require(gradualUpdate.startBlock == 0, "ERR_NO_UPDATE_DURING_GRADUAL");

        // Delegate to library to save space
        SmartPoolManager.updateWeight(
            IConfigurableRightsPool(address(this)),
            corePool,
            token,
            newWeight,
            coreFactory.minimumKacy(),
            coreFactory.kacyToken()
        );
    }

    /**
     * @notice Update weights in a predetermined way, between startBlock and endBlock,
     *         through external calls to pokeWeights
     *
     * @dev Must call pokeWeights at least once past the end for it to do the final update
     *      and enable calling this again.
     *      It is possible to call updateWeightsGradually during an update in some use cases
     *      For instance, setting newWeights to currentWeights to stop the update where it is
     *
     * @param newWeights - Final weights we want to get to. Note that the ORDER (and number) of
     *                     tokens can change if you have added or removed tokens from the pool
     *                     It ensures the counts are correct, but can't help you with the order!
     *                     You can get the underlying core Pool (it's public), and call
     *                     getCurrentTokens() to see the current ordering, if you're not sure
     * @param startBlock - When weights should start to change
     * @param endBlock - When weights will be at their final values
     */
    function updateWeightsGradually(
        uint[] calldata newWeights,
        uint startBlock,
        uint endBlock
    )
        external
        override
        lock
        logs
        needsCorePool
        onlyStrategy
        virtual
    {
        require(rights.canChangeWeights, "ERR_NOT_CONFIGURABLE_WEIGHTS");
        // Don't start this when we're in the middle of adding a new token
        require(!newToken.isCommitted, "ERR_PENDING_TOKEN_ADD");

        // Library computes the startBlock, computes startWeights as the current
        // denormalized weights of the core pool tokens.
        SmartPoolManager.updateWeightsGradually(
            corePool,
            gradualUpdate,
            newWeights,
            startBlock,
            endBlock,
            minimumWeightChangeBlockPeriod,
            coreFactory.minimumKacy(),
            coreFactory.kacyToken()
        );
    }

    /**
     * @notice External function called to make the contract update weights according to plan
     *
     * @dev Still works if we poke after the end of the period; also works if the weights don't change
     *      Resets if we are poking beyond the end, so that we can do it again
     */
    function pokeWeights()
        external
        override
        lock
        logs
        needsCorePool
        virtual
    {
        require(rights.canChangeWeights, "ERR_NOT_CONFIGURABLE_WEIGHTS");

        // Delegate to library to save space
        SmartPoolManager.pokeWeights(corePool, gradualUpdate);
    }

    /**
     * @notice Schedule (commit) a token to be added; must call applyAddToken after a fixed
     *         number of blocks to actually add the token
     *
     * @dev The purpose of this two-stage commit is to give warning of a potentially dangerous
     *      operation. A malicious pool operator could add a large amount of a low-value token,
     *      then drain the pool through price manipulation. Of course, there are many
     *      legitimate purposes, such as adding additional collateral tokens.
     *
     * @param token - Address of the token to be added
     * @param balance - How much to be added
     * @param denormalizedWeight - Desired token weight
     */
    function commitAddToken(
        address token,
        uint balance,
        uint denormalizedWeight
    )
        external
        override
        lock
        logs
        onlyStrategy
        needsCorePool
        virtual
    {
        require(rights.canAddRemoveTokens, "ERR_CANNOT_ADD_REMOVE_TOKENS");

        // Can't do this while a progressive update is happening
        require(gradualUpdate.startBlock == 0, "ERR_NO_UPDATE_DURING_GRADUAL");

        SmartPoolManager.verifyTokenCompliance(token);

        emit NewTokenCommitted(token, address(this), msg.sender);

        // Delegate to library to save space
        SmartPoolManager.commitAddToken(
            corePool,
            token,
            balance,
            denormalizedWeight,
            newToken
        );
    }

    /**
     * @notice Add the token previously committed (in commitAddToken) to the pool
     *
     * @dev Caller must have the token available to include it in the pool
     */
    function applyAddToken()
        external
        override
        lock
        logs
        onlyStrategy
        needsCorePool
        virtual
    {
        require(rights.canAddRemoveTokens, "ERR_CANNOT_ADD_REMOVE_TOKENS");

        // Delegate to library to save space
        SmartPoolManager.applyAddToken(
            IConfigurableRightsPool(address(this)),
            corePool,
            addTokenTimeLockInBlocks,
            newToken
        );
    }

    /**
     * @notice Remove a token from the pool
     *
     * @dev corePool is a contract interface; function calls on it are external
     *
     * @param token - Address of the token to remove
     */
    function removeToken(address token)
        external
        override
        lock
        logs
        onlyStrategy
        needsCorePool
    {
        // It's possible to have remove rights without having add rights
        require(rights.canAddRemoveTokens,"ERR_CANNOT_ADD_REMOVE_TOKENS");
        // After createPool, token list is maintained in the underlying core Pool
        require(!newToken.isCommitted, "ERR_REMOVE_WITH_ADD_PENDING");
        // Prevent removing during an update (or token lists can get out of sync)
        require(gradualUpdate.startBlock == 0, "ERR_NO_UPDATE_DURING_GRADUAL");
        // can't remove $KACY (core pool also checks but we can fail earlier)
        require(token != coreFactory.kacyToken(), "ERR_MIN_KACY");

        // Delegate to library to save space
        SmartPoolManager.removeToken(IConfigurableRightsPool(address(this)), corePool, token);
    }

    /**
     * @notice Join a pool - mint pool tokens with underlying assets
     *
     * @dev Emits a LogJoin event for each token
     *      corePool is a contract interface; function calls on it are external
     *
     * @param poolAmountOut - Number of pool tokens to receive
     * @param maxAmountsIn - Max amount of asset tokens to spend; will follow the pool order
     */
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external
        lock
        needsCorePool
        lockUnderlyingPool
        logs
    {
        require(!rights.canWhitelistLPs || _liquidityProviderWhitelist[msg.sender],
                "ERR_NOT_ON_WHITELIST");

        // Delegate to library to save space

        // Library computes actualAmountsIn, and does many validations
        // Cannot call the push/pull/min from an external library for
        // any of these pool functions. Since msg.sender can be anybody,
        // they must be internal
        uint[] memory actualAmountsIn = SmartPoolManager.joinPool(
            IConfigurableRightsPool(address(this)),
            corePool,
            poolAmountOut,
            maxAmountsIn
        );

        // After createPool, token list is maintained in the underlying core Pool
        address[] memory poolTokens = corePool.getCurrentTokens();

        for (uint i = 0; i < poolTokens.length; i++) {
            address t = poolTokens[i];
            uint tokenAmountIn = actualAmountsIn[i];

            emit LogJoin(msg.sender, t, tokenAmountIn);

            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    /**
     * @notice Exit a pool - redeem/burn pool tokens for underlying assets
     *
     * @dev Emits a LogExit event for each token
     *      corePool is a contract interface; function calls on it are external
     *
     * @param poolAmountIn - amount of pool tokens to redeem
     * @param minAmountsOut - minimum amount of asset tokens to receive
     */
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external
        lock
        needsCorePool
        lockUnderlyingPool
        logs
    {
        // Delegate to library to save space

        // Library computes actualAmountsOut, and does many validations
        // Also computes the exitFee and pAiAfterExitFee
        (
            uint exitFee,
            uint pAiAfterExitFee,
            uint[] memory actualAmountsOut
        ) = SmartPoolManager.exitPool(
            IConfigurableRightsPool(address(this)),
            corePool,
            poolAmountIn,
            minAmountsOut
        );

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(address(coreFactory), exitFee);
        _burnPoolShare(pAiAfterExitFee);

        // After createPool, token list is maintained in the underlying core Pool
        address[] memory poolTokens = corePool.getCurrentTokens();

        for (uint i = 0; i < poolTokens.length; i++) {
            address t = poolTokens[i];
            uint tokenAmountOut = actualAmountsOut[i];

            emit LogExit(msg.sender, t, tokenAmountOut);

            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }
    }

    /**
     * @notice Join by swapping a fixed amount of an external token in (must be present in the pool)
     *         System calculates the pool token amount
     *
     * @dev emits a LogJoin event
     *
     * @param tokenIn - Which token we're transferring in
     * @param tokenAmountIn - Amount of the deposit
     * @param minPoolAmountOut - Minimum of pool tokens to receive
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function joinswapExternAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut
    )
        external
        lock
        logs
        needsCorePool
        returns (uint poolAmountOut)
    {
        require(!rights.canWhitelistLPs || _liquidityProviderWhitelist[msg.sender],
                "ERR_NOT_ON_WHITELIST");

        // Delegate to library to save space
        poolAmountOut = SmartPoolManager.joinswapExternAmountIn(
            IConfigurableRightsPool(address(this)),
            corePool,
            tokenIn,
            tokenAmountIn,
            minPoolAmountOut
        );

        emit LogJoin(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
    }

    /**
     * @notice Join by swapping an external token in (must be present in the pool)
     *         To receive an exact amount of pool tokens out. System calculates the deposit amount
     *
     * @dev emits a LogJoin event
     *
     * @param tokenIn - Which token we're transferring in (system calculates amount required)
     * @param poolAmountOut - Amount of pool tokens to be received
     * @param maxAmountIn - Maximum asset tokens that can be pulled to pay for the pool tokens
     *
     * @return tokenAmountIn - Amount of asset tokens transferred in to purchase the pool tokens
     */
    function joinswapPoolAmountOut(
        address tokenIn,
        uint poolAmountOut,
        uint maxAmountIn
    )
        external
        lock
        logs
        needsCorePool
        returns (uint tokenAmountIn)
    {
        require(!rights.canWhitelistLPs || _liquidityProviderWhitelist[msg.sender],
                "ERR_NOT_ON_WHITELIST");

        // Delegate to library to save space
        tokenAmountIn = SmartPoolManager.joinswapPoolAmountOut(
            IConfigurableRightsPool(address(this)),
            corePool,
            tokenIn,
            poolAmountOut,
            maxAmountIn
        );

        emit LogJoin(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
    }

    /**
     * @notice Exit a pool - redeem a specific number of pool tokens for an underlying asset
     *         Asset must be present in the pool, and will incur an EXIT_FEE (if set to non-zero)
     *
     * @dev Emits a LogExit event for the token
     *
     * @param tokenOut - Which token the caller wants to receive
     * @param poolAmountIn - Amount of pool tokens to redeem
     * @param minAmountOut - Minimum asset tokens to receive
     *
     * @return tokenAmountOut - Amount of asset tokens returned
     */
    function exitswapPoolAmountIn(
        address tokenOut,
        uint poolAmountIn,
        uint minAmountOut
    )
        external
        lock
        logs
        needsCorePool
        returns (uint tokenAmountOut)
    {
        // Delegate to library to save space

        // Calculates final amountOut, and the fee and final amount in
        (uint exitFee, uint amountOut) = SmartPoolManager.exitswapPoolAmountIn(
            IConfigurableRightsPool(address(this)),
            corePool,
            tokenOut,
            poolAmountIn,
            minAmountOut
        );

        tokenAmountOut = amountOut;
        uint pAiAfterExitFee = poolAmountIn - exitFee;

        emit LogExit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(pAiAfterExitFee);
        _pushPoolShare(address(coreFactory), exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    /**
     * @notice Exit a pool - redeem pool tokens for a specific amount of underlying assets
     *         Asset must be present in the pool
     *
     * @dev Emits a LogExit event for the token
     *
     * @param tokenOut - Which token the caller wants to receive
     * @param tokenAmountOut - Amount of underlying asset tokens to receive
     * @param maxPoolAmountIn - Maximum pool tokens to be redeemed
     *
     * @return poolAmountIn - Amount of pool tokens redeemed
     */
    function exitswapExternAmountOut(
        address tokenOut,
        uint tokenAmountOut,
        uint maxPoolAmountIn
    )
        external
        lock
        logs
        needsCorePool
        returns (uint poolAmountIn)
    {
        // Delegate to library to save space

        // Calculates final amounts in, accounting for the exit fee
        (uint exitFee, uint amountIn) = SmartPoolManager.exitswapExternAmountOut(
            IConfigurableRightsPool(address(this)),
            corePool,
            tokenOut,
            tokenAmountOut,
            maxPoolAmountIn
        );

        poolAmountIn = amountIn;
        uint pAiAfterExitFee = poolAmountIn - exitFee;

        emit LogExit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(pAiAfterExitFee);
        _pushPoolShare(address(coreFactory), exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    /**
     * @notice Add to the whitelist of liquidity providers (if enabled)
     *
     * @param provider - address of the liquidity provider
     */
    function whitelistLiquidityProvider(address provider)
        external
        lock
        logs
        onlyOwner
    {
        require(rights.canWhitelistLPs, "ERR_CANNOT_WHITELIST_LPS");
        require(provider != address(0), "ERR_INVALID_ADDRESS");

        _liquidityProviderWhitelist[provider] = true;
    }

    /**
     * @notice Remove from the whitelist of liquidity providers (if enabled)
     *
     * @param provider - address of the liquidity provider
     */
    function removeWhitelistedLiquidityProvider(address provider)
        external
        lock
        logs
        onlyOwner
    {
        require(rights.canWhitelistLPs, "ERR_CANNOT_WHITELIST_LPS");
        require(_liquidityProviderWhitelist[provider], "ERR_LP_NOT_WHITELISTED");
        require(provider != address(0), "ERR_INVALID_ADDRESS");

        _liquidityProviderWhitelist[provider] = false;
    }

    /**
     * @notice Getter for the publicSwap field on the underlying pool
     *
     * @dev viewLock, because setPublicSwap is lock
     *      corePool is a contract interface; function calls on it are external
     *
     * @return Current value of isPublicSwap
     */
    function isPublicSwap()
        external
        view
        viewlock
        needsCorePool
        virtual
        returns (bool)
    {
        return corePool.isPublicSwap();
    }

    /**
     * @notice Check if an address is a liquidity provider
     *
     * @dev If the whitelist feature is not enabled, anyone can provide liquidity (assuming finalized)
     *
     * @param provider - Address to check if it can become a liquidity provider
     *
     * @return Boolean value indicating whether the address can join a pool
     */
    function canProvideLiquidity(address provider)
        external
        view
        returns (bool)
    {
        if (rights.canWhitelistLPs) {
            return _liquidityProviderWhitelist[provider];
        }
        else {
            // Probably don't strictly need this (could just return true)
            // But the null address can't provide funds
            return provider != address(0);
        }
    }

    /**
     * @notice Getter for specific permissions
     *
     * @dev value of the enum is just the 0-based index in the enumeration
     *      For instance canPauseSwapping is 0; canChangeWeights is 2
     *
     * @param permission - What permission to check
     *
     * @return Boolean true if we have the given permission
    */
    function hasPermission(RightsManager.Permissions permission)
        external
        view
        virtual
        returns (bool)
    {
        return RightsManager.hasPermission(rights, permission);
    }

    /**
     * @notice Get the denormalized weight of a token
     *
     * @dev viewlock to prevent calling if it's being updated
     *
     * @param token - Address of the token to get the denormalized weight
     *
     * @return Denormalized token weight
     */
    function getDenormalizedWeight(address token)
        external
        view
        viewlock
        needsCorePool
        returns (uint)
    {
        return corePool.getDenormalizedWeight(token);
    }

    /**
     * @notice Getter for the RightsManager contract
     *
     * @dev Convenience function to get the address of the RightsManager library (so clients can check version)
     *
     * @return Address of the RightsManager library
    */
    function getRightsManagerVersion() external pure returns (address) {
        return address(RightsManager);
    }

    /**
     * @notice Getter for the SmartPoolManager contract
     *
     * @dev Convenience function to get the address of the SmartPoolManager library (so clients can check version)
     *
     * @return Address of the SmartPoolManager library
    */
    function getSmartPoolManagerVersion() external pure returns (address) {
        return address(SmartPoolManager);
    }

    // Public functions
    // "Public" versions that can safely be called from SmartPoolManager
    // Allows only the contract itself to call them (not the controller or any external account)

    /// Can only be called by the SmartPoolManager library, will fail otherwise
    function mintPoolShareFromLib(uint amount) public override {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _mint(amount);
    }

    /// Can only be called by the SmartPoolManager library, will fail otherwise
    function pushPoolShareFromLib(address to, uint amount) public override {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _push(to, amount);
    }

    /// Can only be called by the SmartPoolManager library, will fail otherwise
    function pullPoolShareFromLib(address from, uint amount) public override {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _pull(from, amount);
    }

    /// Can only be called by the SmartPoolManager library, will fail otherwise
    function burnPoolShareFromLib(uint amount) public override {
        require (msg.sender == address(this), "ERR_NOT_CONTROLLER");

        _burn(amount);
    }

    // Internal functions
    // Lint wants the function to have a leading underscore too
    /* solhint-disable private-vars-leading-underscore */

    /**
     * @notice Create a new Smart Pool
     *
     * @dev Initialize the swap fee to the value provided in the CRP constructor
     *      Can be changed if the canChangeSwapFee permission is enabled
     *
     * @param initialSupply - Starting pool token balance
     */
    function createPoolInternal(uint initialSupply) internal {
        require(address(corePool) == address(0), "ERR_IS_CREATED");
        require(initialSupply >= KassandraConstants.MIN_POOL_SUPPLY, "ERR_INIT_SUPPLY_MIN");
        require(initialSupply <= KassandraConstants.MAX_POOL_SUPPLY, "ERR_INIT_SUPPLY_MAX");

        // If the controller can change the cap, initialize it to the initial supply
        // Defensive programming, so that there is no gap between creating the pool
        // (initialized to unlimited in the constructor), and setting the cap,
        // which they will presumably do if they have this right.
        if (rights.canChangeCap) {
            tokenCap = initialSupply;
        }

        // There is technically reentrancy here, since we're making external calls and
        // then transferring tokens. However, the external calls are all to the underlying core Pool

        // To the extent possible, modify state variables before calling functions
        _mintPoolShare(initialSupply);
        _pushPoolShare(msg.sender, initialSupply);

        // Deploy new core Pool (coreFactory and corePool are interfaces; all calls are external)
        corePool = coreFactory.newPool();

        for (uint i = 0; i < _initialTokens.length; i++) {
            address t = _initialTokens[i];
            uint bal = _initialBalances[i];
            uint denorm = gradualUpdate.startWeights[i];

            bool returnValue = IERC20(t).transferFrom(msg.sender, address(this), bal);
            require(returnValue, "ERR_ERC20_FALSE");

            returnValue = IERC20(t).safeApprove(address(corePool), KassandraConstants.MAX_UINT);
            require(returnValue, "ERR_ERC20_FALSE");

            corePool.bind(t, bal, denorm);
        }

        while (_initialTokens.length > 0) {
            // Modifying state variable after external calls here,
            // but not essential, so not dangerous
            _initialTokens.pop();
        }

        // Set fee to the initial value set in the constructor
        // Hereafter, read the swapFee from the underlying pool, not the local state variable
        corePool.setSwapFee(_initialSwapFee);
        corePool.setPublicSwap(true);

        // "destroy" the temporary swap fee (like _initialTokens above) in case a subclass tries to use it
        _initialSwapFee = 0;
    }

    /* solhint-enable private-vars-leading-underscore */

    /**
     * @dev Rebind core Pool and pull tokens from address
     *      Will get tokens from somewhere to send to the underlying core pool
     *
     *      corePool is a contract interface; function calls on it are external
     *
     * @param erc20 - Address of the token being pulled
     * @param from - Address of the owner of the tokens being pulled
     * @param amount - How much tokens are being transferred
     */
    function _pullUnderlying(address erc20, address from, uint amount) internal needsCorePool {
        // Gets current Balance of token i, Bi, and weight of token i, Wi, from core Pool.
        uint tokenBalance = corePool.getBalance(erc20);
        uint tokenWeight = corePool.getDenormalizedWeight(erc20);

        // transfer tokens to this contract
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
        // and then send it to the core pool
        corePool.rebind(erc20, tokenBalance + amount, tokenWeight);
    }

    /**
     * @dev Rebind core Pool and push tokens to address
     *      Will get tokens from the core pool and send to some address
     *
     *      corePool is a contract interface; function calls on it are external
     *
     * @param erc20 - Address of the token being sent
     * @param to - Address where the tokens are being pushed to
     * @param amount - How much tokens are being transferred
     */
    function _pushUnderlying(address erc20, address to, uint amount) internal needsCorePool {
        // Gets current Balance of token i, Bi, and weight of token i, Wi, from core Pool.
        uint tokenBalance = corePool.getBalance(erc20);
        uint tokenWeight = corePool.getDenormalizedWeight(erc20);
        // get the amount of tokens from the underlying pool to this contract
        corePool.rebind(erc20, tokenBalance - amount, tokenWeight);

        // and transfer them to the address
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    // Wrappers around corresponding core functions

    /**
     * @dev Wrapper to mint and enforce maximum cap
     *
     * @param amount - Amount to mint
     */
    function _mint(uint amount) internal override {
        super._mint(amount);
        require(_totalSupply <= tokenCap, "ERR_CAP_LIMIT_REACHED");
    }

    /**
     * @dev Mint pool tokens
     *
     * @param amount - How much to mint
     */
    function _mintPoolShare(uint amount) internal {
        _mint(amount);
    }

    /**
     * @dev Send pool tokens to someone
     *
     * @param to - Who should receive the tokens
     * @param amount - How much to send to the address
     */
    function _pushPoolShare(address to, uint amount) internal {
        _push(to, amount);
    }

    /**
     * @dev Get/Receive pool tokens from someone
     *
     * @param from - From whom should tokens be received
     * @param amount - How much to get from address
     */
    function _pullPoolShare(address from, uint amount) internal  {
        _pull(from, amount);
    }

    /**
     * @dev Burn pool tokens
     *
     * @param amount - How much to burn
     */
    function _burnPoolShare(uint amount) internal  {
        _burn(amount);
    }
}
