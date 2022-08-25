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

import "hardhat/console.sol";

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

    uint public investFee = KassandraConstants.ONE * 1 / 100; // 1%
    uint public investFeeRefferal = KassandraConstants.ONE * 1 / 100; // 1%

    mapping(address => mapping(address => Wrappers)) public wrappers;

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
     * @param communityStore_ - Address where contains the whitelist
     */
    constructor(address wNative, address communityStore_) {
        wNativeToken = wNative;
        communityStore = IKassandraCommunityStore(communityStore_);
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
    )
        external
        onlyOwner
    {
        wrappers[corePool][tokenIn] = Wrappers({
            deposit: bytes4(keccak256(bytes(depositSignature))),
            withdraw: bytes4(keccak256(bytes(withdrawSignature))),
            exchange: bytes4(keccak256(bytes(exchangeSignature))),
            wrapContract: wrappedToken,
            creationBlock: block.number
        });

        wrappers[crpPool][tokenIn] = wrappers[corePool][tokenIn];

        IERC20 wToken = IERC20(wrappedToken);
        IERC20(tokenIn).safeApprove(wrappedToken, type(uint).max);
        wToken.safeApprove(corePool, type(uint).max);
        wToken.safeApprove(crpPool, type(uint).max);

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
    * @dev Update Community Store where contains the whitelist
    *
     * @param newCommunityStore - Community store address where contains the whitelist
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
     */
    function joinPool(
        address crpPool,
        uint poolAmountOut,
        address[] calldata tokensIn,
        uint[] calldata maxAmountsIn
    )
        external
        payable
    {
        uint[] memory underlyingMaxAmountsIn = new uint[](maxAmountsIn.length);
        address[] memory underlyingTokens = new address[](maxAmountsIn.length);
        for (uint i = 0; i < tokensIn.length; i++) {
            (underlyingTokens[i], underlyingMaxAmountsIn[i]) = _wrapTokenIn(crpPool, tokensIn[i], maxAmountsIn[i]);
        }

        // execute join
        IConfigurableRightsPool(crpPool).joinPool(
            poolAmountOut,
            underlyingMaxAmountsIn
        );

        IERC20(crpPool).safeTransfer(msg.sender, poolAmountOut);

        for (uint i = 0; i < tokensIn.length; i++) {
            address underlyingTokenOut = tokensIn[i];
            if (wrappers[crpPool][underlyingTokenOut].wrapContract != address(0)) {
                underlyingTokenOut = wrappers[crpPool][underlyingTokenOut].wrapContract;
            }
            uint _tokenAmountOut = IERC20(underlyingTokens[i]).balanceOf(address(this));
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
     * @param poolAmountIn - amount of pool tokens to redeem
     * @param tokensOut - Address of the tokens the user wants to receive
     * @param minAmountsOut - minimum amount of asset tokens to receive
     */
    function exitPool(
        address crpPool,
        uint poolAmountIn,
        address[] calldata tokensOut,
        uint[] calldata minAmountsOut
    )
        external
    {
        uint numTokens = minAmountsOut.length;
        // get the pool tokens from the user to actually execute the exit
        IERC20(crpPool).safeTransferFrom(msg.sender, address(this), poolAmountIn);

        // execute the exit without limits, limits will be tested later
        IConfigurableRightsPool(crpPool).exitPool(
            poolAmountIn,
            new uint[](numTokens)
        );

        // send received tokens to user
        for (uint i = 0; i < numTokens; i++) {
            address underlyingTokenOut = tokensOut[i];

            if (wrappers[crpPool][underlyingTokenOut].wrapContract != address(0)) {
                underlyingTokenOut = wrappers[crpPool][underlyingTokenOut].wrapContract;
            }

            uint tokenAmountOut = IERC20(underlyingTokenOut).balanceOf(address(this));
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
     *
     * @return poolAmountOut - Amount of pool tokens minted and transferred
     */
    function joinswapExternAmountIn(
        address crpPool,
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut,
        address refferal
    )
        external
        payable
        returns (
            uint poolAmountOut
        )
    {
        // get tokens from user and wrap it if necessary
        (address underlyingTokenIn, uint underlyingTokenAmountIn) = _wrapTokenIn(crpPool, tokenIn, tokenAmountIn);

        // execute join and get amount of pool tokens minted
        poolAmountOut = IConfigurableRightsPool(crpPool).joinswapExternAmountIn(
            underlyingTokenIn,
            underlyingTokenAmountIn,
            minPoolAmountOut
        );
    
        uint _feesToManager = KassandraSafeMath.bmul(poolAmountOut, investFee);
        uint _feesToRefferal = KassandraSafeMath.bmul(poolAmountOut, investFeeRefferal);
        uint _poolAmountOut = poolAmountOut - (_feesToRefferal + _feesToManager);
        address _manager = communityStore.poolToManager(crpPool);

        if(refferal == address(0)) {
            refferal = _manager;
        }
        
        IERC20(crpPool).safeTransfer(msg.sender, _poolAmountOut);
        IERC20(crpPool).safeTransfer(_manager, _feesToManager);
        IERC20(crpPool).safeTransfer(refferal, _feesToRefferal);
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
     *
     * @return tokenAmountIn - Amount of asset tokens transferred in to purchase the pool tokens
     */
    function joinswapPoolAmountOut(
        address crpPool,
        address tokenIn,
        uint poolAmountOut,
        uint maxAmountIn,
        address refferal
    )
        external
        payable
        returns (
            uint tokenAmountIn
        )
    {
        // get tokens from user and wrap it if necessary
        (address underlyingTokenIn, uint underlyingMaxAmountIn) = _wrapTokenIn(crpPool, tokenIn, maxAmountIn);

        uint _poolAmountOut = KassandraSafeMath.bdiv(
            poolAmountOut, KassandraConstants.ONE - investFee - investFeeRefferal);
        uint _feesToManager = KassandraSafeMath.bmul(_poolAmountOut, investFee);
        uint _feesToRefferal = KassandraSafeMath.bmul(_poolAmountOut, investFeeRefferal);
        address _manager = communityStore.poolToManager(crpPool);

        // execute join and get amount of underlying tokens used
        uint underlyingTokenAmountIn = IConfigurableRightsPool(crpPool).joinswapPoolAmountOut(
            underlyingTokenIn,
            _poolAmountOut,
            underlyingMaxAmountIn
        );

        if(refferal == address(0)) {
            refferal = _manager;
        }

        // transfer to user the minted pool tokens
        IERC20(crpPool).safeTransfer(msg.sender, poolAmountOut);
        IERC20(crpPool).safeTransfer(_manager, _feesToManager);
        IERC20(crpPool).safeTransfer(refferal, _feesToRefferal);

        // unwrap the tokens that were not used and send to the user
        uint excessTokens = _unwrapTokenOut(
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
        uint poolAmountIn,
        uint minAmountOut
    )
        external
        returns (
            uint tokenAmountOut
        )
    {
        // get the pool tokens from the user to actually execute the exit
        IERC20(crpPool).safeTransferFrom(msg.sender, address(this), poolAmountIn);
        address underlyingTokenOut = tokenOut;

        // check if the token being passed is the unwrapped version of the token inside the pool
        if (wrappers[crpPool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[crpPool][tokenOut].wrapContract;
        }

        // execute the exit and get how many tokens were received, we'll test minimum amount later
        uint underlyingTokenAmountOut = IConfigurableRightsPool(crpPool).exitswapPoolAmountIn(
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
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external
        payable
        returns (
            uint tokenAmountOut,
            uint spotPriceAfter
        )
    {
        address underlyingTokenIn;
        address underlyingTokenOut = tokenOut;

        if (wrappers[corePool][tokenOut].wrapContract != address(0)) {
            underlyingTokenOut = wrappers[corePool][tokenOut].wrapContract;
        }

        (underlyingTokenIn, tokenAmountIn) = _wrapTokenIn(corePool, tokenIn, tokenAmountIn);

        uint tokenInExchange = exchangeRate(corePool, tokenIn);
        uint tokenOutExchange = exchangeRate(corePool, tokenOut);

        maxPrice = KassandraSafeMath.bdiv(KassandraSafeMath.bmul(maxPrice, tokenInExchange), tokenOutExchange);
        minAmountOut = KassandraSafeMath.bmul(minAmountOut, tokenOutExchange);

        // do the swap and get the output
        (uint underlyingTokenAmountOut, uint underlyingSpotPriceAfter) = IPool(corePool).swapExactAmountIn(
            underlyingTokenIn,
            tokenAmountIn,
            underlyingTokenOut,
            minAmountOut,
            maxPrice
        );

        tokenAmountOut = _unwrapTokenOut(corePool, tokenOut, underlyingTokenOut, underlyingTokenAmountOut);
        spotPriceAfter = KassandraSafeMath.bdiv(
            KassandraSafeMath.bmul(underlyingSpotPriceAfter, tokenInExchange), tokenOutExchange);
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
    )
        public
        view
        returns (
            uint price
        )
    {
        uint tokenInExchange = exchangeRate(corePool, tokenIn);
        uint tokenOutExchange = exchangeRate(corePool, tokenOut);

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
    )
        public
        view
        returns (
            uint price
        )
    {
        uint tokenInExchange = exchangeRate(corePool, tokenIn);
        uint tokenOutExchange = exchangeRate(corePool, tokenOut);

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
    function exchangeRate(
        address pool,
        address token
    )
        public
        view
        returns(
            uint tokenExchange
        )
    {
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

    function _wrapTokenIn(
        address pool,
        address tokenIn,
        uint tokenAmountIn
    )
        private
        returns(
            address wrappedTokenIn,
            uint wrappedTokenAmountIn
        )
    {
        address wrapContract = wrappers[pool][tokenIn].wrapContract;
        uint avaxIn;

        // if the user don't send the native token we don't need to wrap it
        if (tokenIn == wNativeToken) {
            if (wrapContract != address(0)) {
                avaxIn = msg.value;

                if (msg.value == 0) {
                    // get the token from the user so the contract can do the withdrawal
                    IERC20(wNativeToken).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
                    IWrappedNative(wNativeToken).withdraw(tokenAmountIn);
                    avaxIn = tokenAmountIn;
                }
            } else if (msg.value > 0) {
                // get the native token from the user and wrap it in the ERC20 compatible contract
                IWrappedNative(wNativeToken).deposit{value: msg.value}();
            }
        } else {
            // get the token from the user so the contract can do the swap
            IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenAmountIn);
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
            IERC20(wrappedTokenIn).safeApprove(pool, type(uint).max);
        }
    }

    function _unwrapTokenOut(
        address pool,
        address tokenOut,
        address wrappedTokenOut,
        uint tokenAmountOut
    )
        private
        returns (
            uint unwrappedTokenAmountOut
        )
    {
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

    receive() external payable {}
}
