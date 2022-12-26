//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "../libraries/SafeERC20.sol";
import "../libraries/KassandraSafeMath.sol";
import "../libraries/KassandraConstants.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IWrappedNative.sol";
import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IKassandraCommunityStore.sol";

import "../utils/Ownable.sol";

contract HermesProxy is Ownable {
    using SafeERC20 for IERC20;

    struct Wrappers {
        bytes4 deposit;
        bytes4 withdraw;
        bytes4 exchange;
        address wrapContract;
        uint256 creationBlock;
    }

    /// Native wrapped token address
    address public immutable wNativeToken;
    IKassandraCommunityStore public communityStore;
    address public swapProvider;

    mapping(address => mapping(address => Wrappers)) public wrappers;

    /**
     * @notice Emitted when a token has been set to be wrapped before entering the pool.
     *         This allows the pool to use some uncommon wrapped token, like an autocompounding
     *         protocol, while allowing the user to spend the common token being wrapped.
     *
     * @param crpPool - CRP address that uses this token
     * @param corePool - Core pool of the above CRP
     * @param tokenIn - Token that is not part of the pool but that will be made available for wrapping
     * @param wrappedToken - Underlying token the above token will be wrapped into, this is the token in the pool
     * @param depositSignature - Function signature for the wrapping function
     * @param withdrawSignature - Function signature for the unwrapping function
     * @param exchangeSignature - Function signature for the exchange rate function
     */
    event NewWrapper(
        address indexed crpPool,
        address indexed corePool,
        address indexed tokenIn,
        address         wrappedToken,
        string          depositSignature,
        string          withdrawSignature,
        string          exchangeSignature
    );

    /**
     * @notice Set the native token address on creation as it can't be changed
     *
     * @param wNative - The wrapped native blockchain token contract
     * @param communityStore_ - Address of contract that holds the list of whitelisted tokens
     * @param swapProvider_ - Address of a DEX contract that allows swapping tokens
     */
    constructor(
        address wNative,
        address communityStore_,
        address swapProvider_
    ) {
        wNativeToken = wNative;
        communityStore = IKassandraCommunityStore(communityStore_);
        swapProvider = swapProvider_;
    }

    /**
     * @notice Create a wrap interface for automatic wrapping and unwrapping any token.
     *
     * @param crpPool - CRP address that uses this token
     * @param corePool - Core pool of the above CRP
     * @param tokenIn - Token that is not part of the pool but that will be made available for wrapping
     * @param wrappedToken - Underlying token the above token will be wrapped into, this is the token in the pool
     * @param depositSignature - Function signature for the wrapping function
     * @param withdrawSignature - Function signature for the unwrapping function
     * @param exchangeSignature - Function signature for the exchange rate function
     */
    function setTokenWrapper(
        address crpPool,
        address corePool,
        address tokenIn,
        address wrappedToken,
        string memory depositSignature,
        string memory withdrawSignature,
        string memory exchangeSignature
    ) external onlyOwner {
        wrappers[corePool][tokenIn] = Wrappers({
            deposit: bytes4(keccak256(bytes(depositSignature))),
            withdraw: bytes4(keccak256(bytes(withdrawSignature))),
            exchange: bytes4(keccak256(bytes(exchangeSignature))),
            wrapContract: wrappedToken,
            creationBlock: block.number
        });

        wrappers[crpPool][tokenIn] = wrappers[corePool][tokenIn];

        IERC20 wToken = IERC20(wrappedToken);
        IERC20(tokenIn).approve(wrappedToken, type(uint256).max);
        wToken.approve(corePool, type(uint256).max);
        wToken.approve(crpPool, type(uint256).max);

        emit NewWrapper(
            crpPool,
            corePool,
            tokenIn,
            wrappedToken,
            depositSignature,
            withdrawSignature,
            exchangeSignature
        );
    }

    /**
     * @dev Change Swap Provider contract
     *
     * @param newSwapProvider - Address of a DEX contract that allows swapping tokens
     */
    function setSwapProvider(address newSwapProvider) external onlyOwner {
        swapProvider = newSwapProvider;
    }

    /**
     * @dev Change Community Store contract
     *
     * @param newCommunityStore - Address of contract that holds the list of whitelisted tokens
     */
    function updateCommunityStore(address newCommunityStore) external onlyOwner {
        require(newCommunityStore != address(0), "ERR_ZERO_ADDRESS");
        communityStore = IKassandraCommunityStore(newCommunityStore);
    }

    /**
     * @notice Join a pool - mint pool tokens with underlying assets
     *
     * @dev Emits a LogJoin event for each token
     *      corePool is a contract interface; function calls on it are external
     *
     * @param crpPool - CRP the user want to interact with
     * @param poolAmountOut - Number of pool tokens to receive
     * @param tokensIn - Address of the tokens the user is sending
     * @param maxAmountsIn - Max amount of asset tokens to spend; will follow the pool order
     * @param referral - Broker address to receive fees
     */
    function joinPool(
        address crpPool,
        uint256 poolAmountOut,
        address[] calldata tokensIn,
        uint256[] calldata maxAmountsIn,
        address referral
    ) external payable {
        uint256[] memory underlyingMaxAmountsIn = new uint256[](maxAmountsIn.length);
        address[] memory underlyingTokens = new address[](maxAmountsIn.length);

        for (uint256 i = 0; i < tokensIn.length; i++) {
            if(msg.value == 0 || tokensIn[i] != wNativeToken) {
                IERC20(tokensIn[i]).safeTransferFrom(msg.sender, address(this), maxAmountsIn[i]);
            }

            (underlyingTokens[i], underlyingMaxAmountsIn[i]) = _wrapTokenIn(crpPool, tokensIn[i], maxAmountsIn[i]);
        }

        {
            IKassandraCommunityStore.PoolInfo memory poolInfo = communityStore.getPoolInfo(crpPool);
            require(
                !poolInfo.isPrivate || communityStore.getPrivateInvestor(crpPool, msg.sender), 
                "ERR_INVESTOR_NOT_ALLOWED"
            );
            uint256 _poolAmountOut = KassandraSafeMath.bdiv(
                poolAmountOut,
                KassandraConstants.ONE - poolInfo.feesToManager - poolInfo.feesToReferral
            );
            uint256 _feesToManager = KassandraSafeMath.bmul(_poolAmountOut, poolInfo.feesToManager);
            uint256 _feesToReferral = KassandraSafeMath.bmul(_poolAmountOut, poolInfo.feesToReferral);
            IConfigurableRightsPool(crpPool).joinPool(_poolAmountOut, underlyingMaxAmountsIn);

            if (referral == address(0)) {
                referral = poolInfo.manager;
            }

            IERC20 crpPoolToken = IERC20(crpPool);
            crpPoolToken.safeTransfer(msg.sender, poolAmountOut);
            crpPoolToken.safeTransfer(poolInfo.manager, _feesToManager);
            crpPoolToken.safeTransfer(referral, _feesToReferral);
        }

        for (uint256 i = 0; i < tokensIn.length; i++) {
            address underlyingTokenOut = tokensIn[i];

            if (wrappers[crpPool][underlyingTokenOut].wrapContract != address(0)) {
                underlyingTokenOut = wrappers[crpPool][underlyingTokenOut].wrapContract;
            }

            uint256 _tokenAmountOut = IERC20(underlyingTokens[i]).balanceOf(address(this));
            _unwrapTokenOut(crpPool, underlyingTokenOut, underlyingTokens[i], _tokenAmountOut);
        }
    }

    /**
     * @notice Exit a pool - redeem/burn pool tokens for underlying assets
     *
     * @dev Emits a LogExit event for each token
     *      corePool is a contract interface; function calls on it are external
     *
     * @param crpPool - CRP the user want to interact with
     * @param poolAmountIn - Amount of pool tokens to redeem
     * @param tokensOut - Address of the tokens the user wants to receive
     * @param minAmountsOut - Minimum amount of asset tokens to receive
     */
    function exitPool(
        address crpPool,
        uint256 poolAmountIn,
        address[] calldata tokensOut,
        uint256[] calldata minAmountsOut
    ) external {
        uint256 numTokens = minAmountsOut.length;
        // get the pool tokens from the user to actually execute the exit
        IERC20(crpPool).safeTransferFrom(msg.sender, address(this), poolAmountIn);

        // execute the exit without limits, limits will be tested later
        IConfigurableRightsPool(crpPool).exitPool(poolAmountIn, new uint256[](numTokens));

        // send received tokens to user
        for (uint256 i = 0; i < numTokens; i++) {
            address underlyingTokenOut = tokensOut[i];

            if (wrappers[crpPool][underlyingTokenOut].wrapContract != address(0)) {
                underlyingTokenOut = wrappers[crpPool][underlyingTokenOut].wrapContract;
            }

            uint256 tokenAmountOut = IERC20(underlyingTokenOut).balanceOf(address(this));
            tokenAmountOut = _unwrapTokenOut(crpPool, tokensOut[i], underlyingTokenOut, tokenAmountOut);
            require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
        }
    }

    /**
     * @notice Join by swapping a fixed amount of an external token in (must be present in the pool)
     *         System calculates the pool token amount
     *
     * @dev emits a LogJoin event
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenIn - Which token we're transferring in
     * @param tokenAmountIn - Amount of the deposit
     * @param minPoolAmountOut - Minimum of pool tokens to receive
     * @param referral - Broker Address to receive fees
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function joinswapExternAmountIn(
        address crpPool,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut,
        address referral
    ) external payable returns (uint256 poolAmountOut) {
        if(msg.value == 0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
        } else {
            tokenAmountIn = 0;
        }
        
        return _joinswapExternAmountIn(crpPool, tokenIn, tokenAmountIn, minPoolAmountOut, referral);
    }

    /**
     * @notice Join by swapping a fixed amount of an external token in using a DEX provider to swap the token
     *         (the token does not need to be present in the pool)
     *         System calculates the pool token amount
     *
     * @dev emits a LogJoin event
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenIn - Which token we're transferring in
     * @param tokenAmountIn - Amount of the deposit
     * @param minPoolAmountOut - Minimum of pool tokens to receive
     * @param referral - Broker Address to receive fees
     * @param data - Params encoded for send to swap provider
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function joinswapExternAmountInWithSwap(
        address crpPool,
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenExchange,
        uint256 minPoolAmountOut,
        address referral,
        bytes calldata data
    ) external payable returns (uint256 poolAmountOut) {
        uint balanceTokenExchange = IERC20(tokenExchange).balanceOf(address(this));

        if(msg.value == 0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
            if (IERC20(tokenIn).allowance(address(this), swapProvider) < tokenAmountIn) {
                IERC20(tokenIn).safeApprove(swapProvider, type(uint256).max);
            }
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory response) = swapProvider.call{ value: msg.value }(data);
        require(success, string(response));

        balanceTokenExchange = IERC20(tokenExchange).balanceOf(address(this)) - balanceTokenExchange;

        poolAmountOut = _joinswapExternAmountIn(crpPool, tokenExchange, balanceTokenExchange, minPoolAmountOut, referral);
    }

    /**
     * @notice Join by swapping an external token in (must be present in the pool)
     *         To receive an exact amount of pool tokens out. System calculates the deposit amount
     *
     * @dev emits a LogJoin event
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenIn - Which token we're transferring in (system calculates amount required)
     * @param poolAmountOut - Amount of pool tokens to be received
     * @param maxAmountIn - Maximum asset tokens that can be pulled to pay for the pool tokens
     * @param referral - Broker Address to receive fees
     *
     * @return tokenAmountIn - Amount of asset tokens transferred in to purchase the pool tokens
     */
    function joinswapPoolAmountOut(
        address crpPool,
        address tokenIn,
        uint256 poolAmountOut,
        uint256 maxAmountIn,
        address referral
    ) external payable returns (uint256 tokenAmountIn) {
        // get tokens from user and wrap it if necessary
        if(msg.value == 0) {
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);
        } else {
            maxAmountIn = 0;
        }

        (address underlyingTokenIn, uint256 underlyingMaxAmountIn) = _wrapTokenIn(crpPool, tokenIn, maxAmountIn);

        IKassandraCommunityStore.PoolInfo memory poolInfo = communityStore.getPoolInfo(crpPool);
        require(
            !poolInfo.isPrivate || communityStore.getPrivateInvestor(crpPool, msg.sender), 
            "ERR_INVESTOR_NOT_ALLOWED"
        );
        uint256 _poolAmountOut = KassandraSafeMath.bdiv(
            poolAmountOut,
            KassandraConstants.ONE - poolInfo.feesToManager - poolInfo.feesToReferral
        );
        uint256 _feesToManager = KassandraSafeMath.bmul(
            _poolAmountOut,
            poolInfo.feesToManager
        );
        uint256 _feesToReferral = KassandraSafeMath.bmul(
            _poolAmountOut,
            poolInfo.feesToReferral
        );

        // execute join and get amount of underlying tokens used
        uint256 underlyingTokenAmountIn = IConfigurableRightsPool(crpPool)
            .joinswapPoolAmountOut(
                underlyingTokenIn,
                _poolAmountOut,
                underlyingMaxAmountIn
            );

        if (referral == address(0)) {
            referral = poolInfo.manager;
        }

        IERC20(crpPool).safeTransfer(msg.sender, poolAmountOut);
        IERC20(crpPool).safeTransfer(poolInfo.manager, _feesToManager);
        IERC20(crpPool).safeTransfer(referral, _feesToReferral);

        uint256 excessTokens = _unwrapTokenOut(
            crpPool,
            tokenIn,
            underlyingTokenIn,
            underlyingMaxAmountIn - underlyingTokenAmountIn
        );

        return maxAmountIn - excessTokens;
    }

    /**
     * @notice Exit a pool - redeem a specific number of pool tokens for an underlying asset
     *         Asset must be present in the pool or must be registered as a unwrapped token,
     *         and will incur an _exitFee (if set to non-zero)
     *
     * @dev Emits a LogExit event for the token
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenOut - Which token the caller wants to receive
     * @param poolAmountIn - Amount of pool tokens to redeem
     * @param minAmountOut - Minimum asset tokens to receive
     *
     * @return tokenAmountOut - Amount of asset tokens returned
     */
    function exitswapPoolAmountIn(
        address crpPool,
        address tokenOut,
        uint256 poolAmountIn,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut) {
        // get the pool tokens from the user to actually execute the exit
        IERC20(crpPool).safeTransferFrom(msg.sender, address(this), poolAmountIn);
        address underlyingTokenOut = tokenOut;

        // check if the token being passed is the unwrapped version of the token inside the pool
        if (wrappers[crpPool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[crpPool][tokenOut].wrapContract;
        }

        // execute the exit and get how many tokens were received, we'll test minimum amount later
        uint256 underlyingTokenAmountOut = IConfigurableRightsPool(crpPool).exitswapPoolAmountIn(
            underlyingTokenOut,
            poolAmountIn, 
            0
        );

        // unwrap the token if it's a wrapped version and send it to the user
        tokenAmountOut = _unwrapTokenOut(crpPool, tokenOut, underlyingTokenOut, underlyingTokenAmountOut);

        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");
    }

    /**
     * @notice Exit a pool - redeem pool tokens for a specific amount of underlying assets
     *         Asset must be present in the pool or must be registered as a unwrapped token
     *         and will incur an _exitFee (if set to non-zero)
     *
     * @dev Emits a LogExit event for the token
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenOut - Which token the caller wants to receive
     * @param tokenAmountOut - Amount of asset tokens to receive
     * @param maxPoolAmountIn - Maximum pool tokens to be redeemed
     *
     * @return poolAmountIn - Amount of pool tokens redeemed
     */
    /*function exitswapExternAmountOut(
        address crpPool,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPoolAmountIn
    )
        external
        returns (
            uint poolAmountIn
        )
    {
        IERC20 crpPoolERC = IERC20(crpPool);
        // get the pool tokens from the user to actually execute the exit
        crpPoolERC.safeTransferFrom(msg.sender, address(this), maxPoolAmountIn);
        address underlyingTokenOut = tokenOut;

        // check if the token being passed is the unwrapped version of the token inside the pool
        if (wrappers[crpPool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[crpPool][tokenOut].wrapContract;
        }

        // check if the token being passed is the unwrapped version of the token inside the pool
        uint tokenOutRate = exchangeRate(crpPool, tokenOut);
        tokenAmountOut = KassandraSafeMath.bmul(tokenAmountOut, tokenOutRate);

        // execute the exit and get how many pool tokens were used
        poolAmountIn = IConfigurableRightsPool(crpPool).exitswapExternAmountOut(
            underlyingTokenOut,
            tokenAmountOut,
            maxPoolAmountIn
        );

        // unwrap the token if it's a wrapped version and send it to the user
        _unwrapTokenOut(crpPool, tokenOut, underlyingTokenOut, tokenAmountOut);
        // send back the difference of the maximum and what was used
        crpPoolERC.safeTransfer(msg.sender, maxPoolAmountIn - poolAmountIn);
    }*/

    /**
     * @notice Swap two tokens but sending a fixed amount
     *         This makes sure you spend exactly what you define,
     *         but you can't be sure of how much you'll receive
     *
     * @param corePool - Address of the core pool where the swap will occur
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
        address corePool,
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
        external
        payable
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        address underlyingTokenIn;
        address underlyingTokenOut = tokenOut;

        if (wrappers[corePool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[corePool][tokenOut].wrapContract;
        }

        (underlyingTokenIn, tokenAmountIn) = _wrapTokenIn(corePool, tokenIn, tokenAmountIn);
        uint256 tokenInExchange = exchangeRate(corePool, tokenIn);
        uint256 tokenOutExchange = exchangeRate(corePool, tokenOut);
        maxPrice = KassandraSafeMath.bdiv(KassandraSafeMath.bmul(maxPrice, tokenInExchange), tokenOutExchange);
        minAmountOut = KassandraSafeMath.bmul(minAmountOut, tokenOutExchange);
        // do the swap and get the output
        (uint256 underlyingTokenAmountOut, uint256 underlyingSpotPriceAfter) = IPool(corePool).swapExactAmountIn(
            underlyingTokenIn,
            tokenAmountIn,
            underlyingTokenOut,
            minAmountOut,
            maxPrice
        );
        tokenAmountOut = _unwrapTokenOut(corePool, tokenOut, underlyingTokenOut, underlyingTokenAmountOut);
        spotPriceAfter = KassandraSafeMath.bdiv(
            KassandraSafeMath.bmul(underlyingSpotPriceAfter, tokenInExchange),
            tokenOutExchange
        );
    }

    /**
     * @notice Swap two tokens but receiving a fixed amount
     *         This makes sure you receive exactly what you define,
     *         but you can't be sure of how much you'll be spending
     *
     * @param corePool - Address of the core pool where the swap will occur
     * @param tokenIn - Address of the token you are sending
     * @param maxAmountIn - Maximum amount of the token you are sending you want to spend
     * @param tokenOut - Address of the token you want to receive
     * @param tokenAmountOut - Fixed amount of tokens you want to receive
     * @param maxPrice - Maximum price you want to pay
     *
     * @return tokenAmountIn - Amount of tokens sent
     * @return spotPriceAfter - New price between assets
     */
    /*function swapExactAmountOut(
        address corePool,
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external
        payable
        returns (
            uint tokenAmountIn,
            uint spotPriceAfter
        )
    {
        address underlyingTokenIn;
        address underlyingTokenOut = tokenOut;

        if (wrappers[corePool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[corePool][tokenOut].wrapContract;
        }

        (underlyingTokenIn, maxAmountIn) = _wrapTokenIn(corePool, tokenIn, maxAmountIn);

        uint tokenInExchange = exchangeRate(corePool, tokenIn);
        uint tokenOutExchange = exchangeRate(corePool, tokenOut);
        uint priceExchange = KassandraSafeMath.bdiv(tokenInExchange, tokenOutExchange);

        maxPrice = KassandraSafeMath.bdiv(maxPrice, priceExchange);

        (tokenAmountIn, spotPriceAfter) = IPool(corePool).swapExactAmountOut(
            underlyingTokenIn,
            maxAmountIn,
            underlyingTokenOut,
            tokenAmountOut,
            maxPrice
        );

        spotPriceAfter = KassandraSafeMath.bmul(spotPriceAfter, priceExchange);
        _unwrapTokenOut(corePool, tokenOut, underlyingTokenOut, tokenAmountOut);
        _unwrapTokenOut(corePool, tokenIn, underlyingTokenIn, maxAmountIn - tokenAmountIn);
    }*/

    /**
     * @notice Get the spot price between two tokens considering the swap fee
     *
     * @param corePool - Address of the core pool where the swap will occur
     * @param tokenIn - Address of the token being swapped-in
     * @param tokenOut - Address of the token being swapped-out
     *
     * @return price - Spot price as amount of swapped-in for every swapped-out
     */
    function getSpotPrice(
        address corePool,
        address tokenIn,
        address tokenOut
    ) public view returns (uint256 price) {
        uint256 tokenInExchange = exchangeRate(corePool, tokenIn);
        uint256 tokenOutExchange = exchangeRate(corePool, tokenOut);

        if (wrappers[corePool][tokenIn].wrapContract != address(0)) {
            tokenIn = wrappers[corePool][tokenIn].wrapContract;
        }

        if (wrappers[corePool][tokenOut].wrapContract != address(0)) {
            tokenOut = wrappers[corePool][tokenOut].wrapContract;
        }

        price = KassandraSafeMath.bdiv(
            KassandraSafeMath.bmul(
                IPool(corePool).getSpotPrice(tokenIn, tokenOut),
                tokenInExchange
            ),
            tokenOutExchange
        );
    }

    /**
     * @notice Get the spot price between two tokens if there's no swap fee
     *
     * @param corePool - Address of the core pool where the swap will occur
     * @param tokenIn - Address of the token being swapped-in
     * @param tokenOut - Address of the token being swapped-out
     *
     * @return price - Spot price as amount of swapped-in for every swapped-out
     */
    function getSpotPriceSansFee(
        address corePool,
        address tokenIn,
        address tokenOut
    ) public view returns (uint256 price) {
        uint256 tokenInExchange = exchangeRate(corePool, tokenIn);
        uint256 tokenOutExchange = exchangeRate(corePool, tokenOut);

        if (wrappers[corePool][tokenIn].wrapContract != address(0)) {
            tokenIn = wrappers[corePool][tokenIn].wrapContract;
        }

        if (wrappers[corePool][tokenOut].wrapContract != address(0)) {
            tokenOut = wrappers[corePool][tokenOut].wrapContract;
        }

        price = KassandraSafeMath.bdiv(
            KassandraSafeMath.bmul(
                IPool(corePool).getSpotPriceSansFee(tokenIn, tokenOut),
                tokenInExchange
            ),
            tokenOutExchange
        );
    }

    /**
     * @notice Get the exchange rate of unwrapped tokens for a wrapped token
     *
     * @param pool - CRP or Core Pool where the tokens are used
     * @param token - The token you want to check the exchange rate
     */
    function exchangeRate(address pool, address token) public view returns (uint256 tokenExchange) {
        tokenExchange = KassandraConstants.ONE;

        if (wrappers[pool][token].wrapContract != address(0)) {
            bytes4 exchangeFunction = wrappers[pool][token].exchange;
            token = wrappers[pool][token].wrapContract;

            if (exchangeFunction != bytes4(0)) {
                bytes memory callData = abi.encodePacked(exchangeFunction, tokenExchange);
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, bytes memory response) = token.staticcall(callData);
                require(success, "ERR_DEPOSIT_REVERTED");
                tokenExchange = abi.decode(response, (uint256));
            }
        }
    }

    /**
     * @dev Wraps the token sent if necessary, it won't do anything if there's no wrapping to be done.
     *
     * @param pool - CRP or Core pool address
     * @param tokenIn - Address of the token sent by the user
     * @param tokenAmountIn - The amount of tokenIn
     *
     * @return wrappedTokenIn - Address of the wrapped token
     * @return wrappedTokenAmountIn - The amount of wrappedTokenIn
     */
    function _wrapTokenIn(
        address pool,
        address tokenIn,
        uint256 tokenAmountIn
    ) private returns (address wrappedTokenIn, uint256 wrappedTokenAmountIn) {
        address wrapContract = wrappers[pool][tokenIn].wrapContract;
        uint256 avaxIn;

        if (tokenIn == wNativeToken) {
            if (tokenAmountIn == 0) {
                avaxIn = msg.value;
            }

            if (address(this).balance > 0) { 
                avaxIn = address(this).balance; 
            }
        }

        wrappedTokenIn = tokenIn;
        wrappedTokenAmountIn = tokenAmountIn;

        if (wrapContract != address(0)) {
            wrappedTokenIn = wrapContract;

            bytes memory callData = abi.encodePacked(wrappers[pool][tokenIn].deposit, tokenAmountIn);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory response) = wrappedTokenIn.call{ value: avaxIn }(callData);
            require(success, string(response));
            wrappedTokenAmountIn = IERC20(wrappedTokenIn).balanceOf(address(this));
        }

        // approve the core pool spending tokens sent to this contract so the swap can happen
        if (IERC20(wrappedTokenIn).allowance(address(this), pool) < wrappedTokenAmountIn) {
            IERC20(wrappedTokenIn).safeApprove(pool, type(uint256).max);
        }
    }

    /**
     * @dev Unwraps the token received if necessary, it won't do anything if there's no unwrapping to be done.
     *      The user may request to receive the wrapped token, in this case we won't unwrap too.
     *
     * @param pool - CRP or Core pool address
     * @param tokenOut - Address of the token requested by the user
     * @param wrappedTokenOut - Address of the token received from the pool
     * @param tokenAmountOut - The amount of tokenOut
     *
     * @return unwrappedTokenAmountOut - The amount of tokens to be sent to the user
     */
    function _unwrapTokenOut(
        address pool,
        address tokenOut,
        address wrappedTokenOut,
        uint256 tokenAmountOut
    ) private returns (uint256 unwrappedTokenAmountOut) {
        unwrappedTokenAmountOut = tokenAmountOut;

        if (tokenOut != wrappedTokenOut) {
            bytes memory callData = abi.encodePacked(wrappers[pool][tokenOut].withdraw, tokenAmountOut);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory response) = wrappedTokenOut.call(callData);
            require(success, string(response));
            // require(success, string(abi.encodePacked("ERR_WITHDRAW_REVERTED_", toAsciiString(tokenOut))));
            unwrappedTokenAmountOut = IERC20(tokenOut).balanceOf(address(this));
        }

        if (tokenOut == wNativeToken) {
            // unwrap the wrapped token and send to user unwrapped
            IWrappedNative(wNativeToken).withdraw(unwrappedTokenAmountOut);
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = payable(msg.sender).call{ value: address(this).balance }("");
            require(success, "Failed to send AVAX");
        } else {
            // send the output token to the user
            IERC20(tokenOut).safeTransfer(msg.sender, unwrappedTokenAmountOut);
        }

        return unwrappedTokenAmountOut;
    }

    /**
     * @dev Join by swapping a fixed amount of an external token in (must be present in the pool)
     *      System calculates the pool token amount
     *      This does the actual investment in the pool
     *
     *      emits a LogJoin event
     *
     * @param crpPool - CRP the user want to interact with
     * @param tokenIn - Which token we're transferring in
     * @param tokenAmountIn - Amount of the deposit
     * @param minPoolAmountOut - Minimum of pool tokens to receive
     * @param referral - Broker Address to receive fees
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function _joinswapExternAmountIn(
        address crpPool,
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut,
        address referral
        ) private returns (uint256 poolAmountOut) {

        // get tokens from user and wrap it if necessary
        (address underlyingTokenIn, uint256 underlyingTokenAmountIn) = _wrapTokenIn(crpPool, tokenIn, tokenAmountIn); 

        // execute join and get amount of pool tokens minted
        poolAmountOut = IConfigurableRightsPool(crpPool).joinswapExternAmountIn(
                underlyingTokenIn,
                underlyingTokenAmountIn,
                minPoolAmountOut
            );

        IKassandraCommunityStore.PoolInfo memory poolInfo = communityStore.getPoolInfo(crpPool);
        require(
            !poolInfo.isPrivate || communityStore.getPrivateInvestor(crpPool, msg.sender), 
            "ERR_INVESTOR_NOT_ALLOWED"
        );
        uint256 _feesToManager = KassandraSafeMath.bmul(poolAmountOut, poolInfo.feesToManager);
        uint256 _feesToReferral = KassandraSafeMath.bmul(poolAmountOut, poolInfo.feesToReferral);
        uint256 _poolAmountOut = poolAmountOut - (_feesToReferral + _feesToManager);

        if (referral == address(0)) {
            referral = poolInfo.manager;
        }

        IERC20(crpPool).safeTransfer(msg.sender, _poolAmountOut);
        IERC20(crpPool).safeTransfer(poolInfo.manager, _feesToManager);
        IERC20(crpPool).safeTransfer(referral, _feesToReferral);
    }

    receive() external payable {}
}
