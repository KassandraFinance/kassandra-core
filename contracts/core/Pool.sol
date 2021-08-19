// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./Math.sol";

import "../Token.sol";

import "../utils/Ownable.sol";
import "../utils/ReentrancyGuard.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";

import "../libraries/KassandraConstants.sol";
import "../libraries/KassandraSafeMath.sol";

/**
 * @title Core Pool - Where the tokens really stay
 */
contract Pool is IPoolDef, Ownable, ReentrancyGuard, CPToken, Math {
    // holds information about one token in the pool
    struct Record {
        bool bound;   // is token bound to pool
        uint index;   // private
        uint denorm;  // denormalized weight
        uint balance; // amount in the pool
    }

    // Factory address to push token exitFee to
    address private _factory;
    // true if PUBLIC can call SWAP functions
    bool private _publicSwap;

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint private _swapFee;
    // when the pool is finalized it can't be changed anymore
    bool private _finalized;

    // list of token addresses
    address[] private _tokens;
    // list of token records
    mapping(address=>Record) private _records;
    // total denormalized weight of all tokens in the pool
    uint private _totalWeight;

    /**
     * @notice Emitted when the swap fee changes
     *
     * @param pool - Address of the pool that changed the swap fee
     * @param caller - Address of who changed the swap fee
     * @param oldFee - The old swap fee
     * @param newFee - The new swap fee
     */
    event NewSwapFee(
        address indexed pool,
        address indexed caller,
        uint256         oldFee,
        uint256         newFee
    );

    /**
     * @notice Emitted when a token has its weight changed in the pool
     *
     * @param pool - Address of the pool where the operation ocurred
     * @param caller - Address of who initiated this change
     * @param token - Address of the token that had its weight changed
     * @param oldWeight - The old denormalized weight
     * @param newWeight - The new denormalized weight
     */
    event WeightChanged(
        address indexed pool,
        address indexed caller,
        address indexed token,
        uint256         oldWeight,
        uint256         newWeight
    );

    /**
     * @notice Emitted when a swap is done in the pool
     *
     * @param caller - Who made the swap
     * @param tokenIn - Address of the token was sent to the pool
     * @param tokenOut - Address of the token was swapped-out of the pool
     * @param tokenAmountIn - How much of tokenIn was swapped-in
     * @param tokenAmountOut - How much of tokenOut was swapped-out
     */
    event LogSwap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
    );

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
        uint256         tokenAmountIn
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
        uint256         tokenAmountOut
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
        bytes           data
    ) anonymous;

    /**
     * @dev Logs a call to a function, only needed for external and public function
     */
    modifier logs() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    /**
     * @notice Construct a new core Pool
     *
     * @param tokenSymbol - Symbol for the pool token
     * @param tokenName - Name for the pool token
     */
    constructor(string memory tokenSymbol, string memory tokenName)
        CPToken(tokenSymbol, tokenName)
    {
        _factory = msg.sender;
        _swapFee = KassandraConstants.MIN_FEE;
        _publicSwap = false;
        _finalized = false;
    }

    /**
     * @notice Set the swap fee
     *
     * @param swapFee - in Wei
     */
    function setSwapFee(uint swapFee)
        external override
        lock
        logs
        onlyOwner
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(swapFee >= KassandraConstants.MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= KassandraConstants.MAX_FEE, "ERR_MAX_FEE");
        emit NewSwapFee(address(this), msg.sender, _swapFee, swapFee);
        _swapFee = swapFee;
    }

    /**
     * @notice Set the public swap flag to allow or prevent swapping in the pool
     *
     * @param public_ - New value of the swap status
     */
    function setPublicSwap(bool public_)
        external override
        lock
        logs
        onlyOwner
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= KassandraConstants.MIN_ASSET_LIMIT, "ERR_MIN_TOKENS");
        IFactory factory = IFactory(_factory);
        require(
            factory.minimumKacy() <= KassandraSafeMath.bdiv(_records[factory.kacyToken()].denorm, _totalWeight),
            "ERR_MIN_KACY"
        );
        _publicSwap = public_;
    }

    /**
     * @notice Finalizes setting up the pool, once called the pool can't be modified ever again
     */
    function finalize()
        external
        lock
        logs
        onlyOwner
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(_tokens.length >= KassandraConstants.MIN_ASSET_LIMIT, "ERR_MIN_TOKENS");
        IFactory factory = IFactory(_factory);
        require(
            factory.minimumKacy() <= KassandraSafeMath.bdiv(_records[factory.kacyToken()].denorm, _totalWeight),
            "ERR_MIN_KACY"
        );

        _finalized = true;
        _publicSwap = true;

        _mintPoolShare(KassandraConstants.MIN_POOL_SUPPLY);
        _pushPoolShare(msg.sender, KassandraConstants.MIN_POOL_SUPPLY);
    }

    /**
     * @notice Bind/Add a new token to the pool, caller must have the tokens
     *
     * @dev Bind does not lock because it jumps to `rebind`, which does
     *
     * @param token - Address of the token being added
     * @param balance - Amount of the token being sent
     * @param denorm - Denormalized weight of the token in the pool
     */
    function bind(address token, uint balance, uint denorm)
        external override
        logs
        onlyOwner
        // lock  see explanation above
    {
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(_tokens.length < KassandraConstants.MAX_ASSET_LIMIT, "ERR_MAX_TOKENS");

        _records[token] = Record({
            bound: true,
            index: _tokens.length,
            denorm: 0,    // balance and denorm will be validated
            balance: 0   // and set by `rebind`
        });
        _tokens.push(token);
        rebind(token, balance, denorm);
    }

    /**
     * @notice Unbind/Remove a token from the pool, caller will receive the tokens
     *
     * @param token - Address of the token being removed
     */
    function unbind(address token)
        external override
        lock
        logs
        onlyOwner
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");
        // can't remove kacy
        IFactory factory = IFactory(_factory);
        require(token != factory.kacyToken(), "ERR_MIN_KACY");

        uint tokenBalance = _records[token].balance;

        _totalWeight -= _records[token].denorm;

        emit WeightChanged(address(this), msg.sender, token, _records[token].denorm, 0);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint index = _records[token].index;
        uint last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        _records[token] = Record({
            bound: false,
            index: 0,
            denorm: 0,
            balance: 0
        });

        _pushUnderlying(token, msg.sender, tokenBalance);
    }

    /**
     * @notice Absorb any tokens that have been sent to this contract into the pool as long as it's bound to the pool
     *
     * @param token - Address of the token to absorb
     */
    function gulp(address token)
        external
        lock
        logs
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Join a pool - mint pool tokens with underlying assets
     *
     * @dev Emits a LogJoin event for each token
     *
     * @param poolAmountOut - Number of pool tokens to receive
     * @param maxAmountsIn - Max amount of asset tokens to spend; will follow the pool order
     */
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external
        lock
        logs
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint poolTotal = _totalSupply;
        uint ratio = KassandraSafeMath.bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountIn = KassandraSafeMath.bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _records[t].balance += tokenAmountIn;
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
     *
     * @param poolAmountIn - amount of pool tokens to redeem
     * @param minAmountsOut - minimum amount of asset tokens to receive
     */
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external
        lock
        logs
    {
        require(_finalized, "ERR_NOT_FINALIZED");

        uint poolTotal = _totalSupply;
        uint exitFee = KassandraSafeMath.bmul(poolAmountIn, KassandraConstants.EXIT_FEE);
        uint pAiAfterExitFee = poolAmountIn - exitFee;
        uint ratio = KassandraSafeMath.bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_factory, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountOut = KassandraSafeMath.bmul(ratio, bal);
            require(tokenAmountOut != 0, "ERR_MATH_APPROX");
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
            _records[t].balance -= tokenAmountOut;
            emit LogExit(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }
    }

    /**
     * @notice Swap two tokens but sending a fixed amount
     *         This makes sure you spend exactly what you define,
     *         but you can't be sure of how much you'll receive
     *
     * @param tokenIn - Address of the token you are sending
     * @param tokenAmountIn - Fixed amount of the token you are sending
     * @param tokenOut - Address of the token you want to receive
     * @param minAmountOut - Minimum amount of tokens you want to receive
     * @param maxPrice - Maximum price you want to pay
     *
     * @return tokenAmountOut - Amount of tokens received
     * @return spotPriceAfter - New price between assets
     */
    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external
        lock
        logs
        returns (uint tokenAmountOut, uint spotPriceAfter)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountIn <= KassandraSafeMath.bmul(inRecord.balance, KassandraConstants.MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        uint spotPriceBefore = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = calcOutGivenIn(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountIn,
            _swapFee
        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance += tokenAmountIn;
        outRecord.balance -= tokenAmountOut;

        spotPriceAfter = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= KassandraSafeMath.bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    /**
     * @notice Swap two tokens but receiving a fixed amount
     *         This makes sure you receive exactly what you define,
     *         but you can't be sure of how much you'll be spending
     *
     * @param tokenIn - Address of the token you are sending
     * @param maxAmountIn - Maximum amount of the token you are sending you want to spend
     * @param tokenOut - Address of the token you want to receive
     * @param tokenAmountOut - Fixed amount of tokens you want to receive
     * @param maxPrice - Maximum price you want to pay
     *
     * @return tokenAmountIn - Amount of tokens sent
     * @return spotPriceAfter - New price between assets
     */
    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external
        lock
        logs
        returns (uint tokenAmountIn, uint spotPriceAfter)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(
            tokenAmountOut <= KassandraSafeMath.bmul(outRecord.balance, KassandraConstants.MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        uint spotPriceBefore = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = calcInGivenOut(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            tokenAmountOut,
            _swapFee
        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        inRecord.balance += tokenAmountIn;
        outRecord.balance -= tokenAmountOut;

        spotPriceAfter = calcSpotPrice(
            inRecord.balance,
            inRecord.denorm,
            outRecord.balance,
            outRecord.denorm,
            _swapFee
        );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= KassandraSafeMath.bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
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
    function joinswapExternAmountIn(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external
        lock
        logs
        returns (uint poolAmountOut)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(
            tokenAmountIn <= KassandraSafeMath.bmul(_records[tokenIn].balance, KassandraConstants.MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        Record storage inRecord = _records[tokenIn];

        poolAmountOut = calcPoolOutGivenSingleIn(
            inRecord.balance,
            inRecord.denorm,
            _totalSupply,
            _totalWeight,
            tokenAmountIn,
            _swapFee
        );

        require(poolAmountOut >= minPoolAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance += tokenAmountIn;

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
    function joinswapPoolAmountOut(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external
        lock
        logs
        returns (uint tokenAmountIn)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");

        Record storage inRecord = _records[tokenIn];

        tokenAmountIn = calcSingleInGivenPoolOut(
            inRecord.balance,
            inRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountOut,
            _swapFee
        );

        require(tokenAmountIn != 0, "ERR_MATH_APPROX");
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        require(
            tokenAmountIn <= KassandraSafeMath.bmul(_records[tokenIn].balance, KassandraConstants.MAX_IN_RATIO),
            "ERR_MAX_IN_RATIO"
        );

        inRecord.balance += tokenAmountIn;

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
    function exitswapPoolAmountIn(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external
        lock
        logs
        returns (uint tokenAmountOut)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = calcSingleOutGivenPoolIn(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            poolAmountIn,
            _swapFee
        );

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        require(
            tokenAmountOut <= KassandraSafeMath.bmul(_records[tokenOut].balance, KassandraConstants.MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        outRecord.balance -= tokenAmountOut;

        uint exitFee = KassandraSafeMath.bmul(poolAmountIn, KassandraConstants.EXIT_FEE);

        emit LogExit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn - exitFee);
        _pushPoolShare(_factory, exitFee);
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
    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external
        lock
        logs
        returns (uint poolAmountIn)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(
            tokenAmountOut <= KassandraSafeMath.bmul(_records[tokenOut].balance, KassandraConstants.MAX_OUT_RATIO),
            "ERR_MAX_OUT_RATIO"
        );

        Record storage outRecord = _records[tokenOut];

        poolAmountIn = calcPoolInGivenSingleOut(
            outRecord.balance,
            outRecord.denorm,
            _totalSupply,
            _totalWeight,
            tokenAmountOut,
            _swapFee
        );

        require(poolAmountIn != 0, "ERR_MATH_APPROX");
        require(poolAmountIn <= maxPoolAmountIn, "ERR_LIMIT_IN");

        outRecord.balance -= tokenAmountOut;

        uint exitFee = KassandraSafeMath.bmul(poolAmountIn, KassandraConstants.EXIT_FEE);

        emit LogExit(msg.sender, tokenOut, tokenAmountOut);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn - exitFee);
        _pushPoolShare(_factory, exitFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);
    }

    /**
     * @notice Getter for the publicSwap field
     *
     * @dev viewLock, because setPublicSwap is lock
     *
     * @return Current value of PublicSwap
     */
    function isPublicSwap()
        external view override
        viewlock
        returns (bool)
    {
        return _publicSwap;
    }

    /**
     * @notice Check if pool is finalized, a finalized pool can't be modified ever again
     *
     * @dev viewLock, because finalize is lock
     *
     * @return Boolean indicating if pool is finalized
     */
    function isFinalized()
        external view
        viewlock
        returns (bool)
    {
        return _finalized;
    }

    /**
     * @notice Check if token is bound to the pool
     *
     * @dev viewLock, because bind and unbind are lock
     *
     * @param t - Address of the token to verify
     *
     * @return Boolean telling if token is part of the pool
     */
    function isBound(address t)
        external view override
        viewlock
        returns (bool)
    {
        return _records[t].bound;
    }

    /**
     * @notice Get how many tokens there are in the pool
     *
     * @dev viewLock, because bind and unbind are lock
     *
     * @return How many tokens the pool contains
     */
    function getNumTokens()
        external view
        viewlock
        returns (uint)
    {
        return _tokens.length;
    }

    /**
     * @notice Get addresses of all tokens in the pool
     *
     * @dev viewLock, because bind and unbind are lock
     *
     * @return tokens - List of addresses for ERC20 tokens
     */
    function getCurrentTokens()
        external view override
        viewlock
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    /**
     * @notice Get addresses of all tokens in the pool but only if pool is finalized
     *
     * @dev viewLock, because bind and unbind are lock
     *
     * @return tokens - List of addresses for ERC20 tokens
     */
    function getFinalTokens()
        external view
        viewlock
        returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    /**
     * @notice Get denormalized weight of one token
     *
     * @param token - Address of the token
     *
     * @return Denormalized weight inside the pool
     */
    function getDenormalizedWeight(address token)
        external view override
        viewlock
        returns (uint)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    /**
     * @notice Get the sum of denormalized weights of all tokens in the pool
     *
     * @return Total denormalized weight of the pool
     */
    function getTotalDenormalizedWeight()
        external view override
        viewlock
        returns (uint)
    {
        return _totalWeight;
    }

    /**
     * @notice Get normalized weight of one token
     *         With 100% = 10^18
     *
     * @param token - Address of the token
     *
     * @return Normalized weight/participation inside the pool
     */
    function getNormalizedWeight(address token)
        external view override
        viewlock
        returns (uint)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        uint denorm = _records[token].denorm;
        return KassandraSafeMath.bdiv(denorm, _totalWeight);
    }

    /**
     * @notice Get token balance inside the pool
     *
     * @param token - Address of the token
     *
     * @return How much of that token is in the pool
     */
    function getBalance(address token)
        external view override
        viewlock
        returns (uint)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    /**
     * @notice Get the current swap fee of the pool
     *         Won't change if the pool is "finalized"
     *
     * @dev viewlock, because setSwapFee is lock
     *
     * @return Current swap fee
     */
    function getSwapFee()
        external view override
        viewlock
        returns (uint)
    {
        return _swapFee;
    }

    /**
     * @notice Get the spot price between two tokens considering the swap fee
     *
     * @param tokenIn - Address of the token being swapped-in
     * @param tokenOut - Address of the token being swapped-out
     *
     * @return Spot price as amount of swapped-in for every swapped-out
     */
    function getSpotPrice(address tokenIn, address tokenOut)
        external view
        viewlock
        returns (uint)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, _swapFee);
    }

    /**
     * @notice Get the spot price between two tokens if there's no swap fee
     *
     * @param tokenIn - Address of the token being swapped-in
     * @param tokenOut - Address of the token being swapped-out
     *
     * @return Spot price as amount of swapped-in for every swapped-out
     */
    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external view
        viewlock
        returns (uint)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, 0);
    }

    /**
     * @notice Modify token balance, weights or both
     *
     * @param token - Address of the token being modifier
     * @param balance - New balance; must send if increasing or will receive if reducing
     * @param denorm - New denormalized weight; will cause prices to change
     */
    function rebind(address token, uint balance, uint denorm)
        public override
        lock
        logs
        onlyOwner
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");

        require(denorm >= KassandraConstants.MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= KassandraConstants.MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= KassandraConstants.MIN_CORE_BALANCE, "ERR_MIN_BALANCE");

        // Adjust the denorm and totalWeight
        uint oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _totalWeight += denorm - oldWeight;
            require(_totalWeight <= KassandraConstants.MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
            emit WeightChanged(address(this), msg.sender, token, oldWeight, denorm);
        } else if (denorm < oldWeight) {
            _totalWeight -= oldWeight - denorm;
            emit WeightChanged(address(this), msg.sender, token, oldWeight, denorm);
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint oldBalance = _records[token].balance;
        _records[token].balance = balance;

        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, balance - oldBalance);
        } else if (balance < oldBalance) {
            _pushUnderlying(token, msg.sender, oldBalance - balance);
        }
    }

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `lock` or otherwise ensure reentry-safety

    /**
     * @dev Pull tokens from address to pool
     *
     * @param erc20 - Address of the token being pulled
     * @param from - Address of the owner of the tokens being pulled
     * @param amount - How much tokens are being transferred
     */
    function _pullUnderlying(address erc20, address from, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    /**
     * @dev Push tokens from pool to address
     *
     * @param erc20 - Address of the token being sent
     * @param to - Address where the tokens are being pushed to
     * @param amount - How much tokens are being transferred
     */
    function _pushUnderlying(address erc20, address to, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    /**
     * @dev Get/Receive pool tokens from someone
     *
     * @param from - From whom should tokens be received
     * @param amount - How much to get from address
     */
    function _pullPoolShare(address from, uint amount)
        internal
    {
        _pull(from, amount);
    }

    /**
     * @dev Send pool tokens to someone
     *
     * @param to - Who should receive the tokens
     * @param amount - How much to send to the address
     */
    function _pushPoolShare(address to, uint amount)
        internal
    {
        _push(to, amount);
    }

    /**
     * @dev Mint pool tokens
     *
     * @param amount - How much to mint
     */
    function _mintPoolShare(uint amount)
        internal
    {
        _mint(amount);
    }

    /**
     * @dev Burn pool tokens
     *
     * @param amount - How much to burn
     */
    function _burnPoolShare(uint amount)
        internal
    {
        _burn(amount);
    }
}
