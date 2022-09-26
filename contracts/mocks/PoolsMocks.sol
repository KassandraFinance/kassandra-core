//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "../libraries/KassandraConstants.sol";
import "../libraries/KassandraSafeMath.sol";
import "../libraries/SmartPoolManager.sol";
import "../libraries/SafeERC20.sol";

import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";

/* solhint-disable ordering */

/**
 * @title A mocking library for easing the tests that need a core pool
 */
contract PoolMock is IPoolDef {
    // @dev Current tokens in the pool mocked
    address[] private _currentTokens;
    mapping(address => uint) private _denormWeights;
    mapping(address => uint) private _balances;
    uint private _totalWeight;

    /**
     * @dev This is for fast setting token addresses for mocking purposes
     *
     * @param tokens - An array of addresses
     */
    function mockCurrentTokens(address[] memory tokens) external {
        _currentTokens = tokens;
    }

    // Just implementing the interface so tests don't take too long nor fail

    function setSwapFee(uint swapFee) external override pure {
        swapFee;
        return;
    }

    function setExitFee(uint exitFee) external override pure {
        exitFee;
        return;
    }

    function setPublicSwap(bool publicSwap) external override pure {
        publicSwap;
        return;
    }

    function setExitFeeCollector(address feeCollector) external override pure {
        feeCollector;
        return;
    }

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external pure
        returns (
            uint tokenAmountOut,
            uint spotPriceAfter
        )
    {
        tokenIn;
        tokenAmountIn;
        tokenOut;
        minAmountOut;
        maxPrice;
        return (0, 0);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external pure
        returns (
            uint tokenAmountIn,
            uint spotPriceAfter
        )
    {
        tokenIn;
        maxAmountIn;
        tokenOut;
        tokenAmountOut;
        maxPrice;
        return (0, 0);
    }

    function bind(address token, uint balance, uint denorm) external override {
        _balances[token] = balance;
        _denormWeights[token] = denorm;
        _totalWeight += denorm;
        return;
    }

    function unbind(address token) external override pure {
        token;
        return;
    }

    function rebind(address token, uint balance, uint denorm) external override {
        _balances[token] = balance;
        _totalWeight += denorm;
        _totalWeight -= _denormWeights[token];
        _denormWeights[token] = denorm;
        return;
    }


    function isPublicSwap() external override pure returns (bool) {
        return true;
    }

    function isBound(address token) external override pure returns(bool) {
        token;
        return true;
    }

    function getCurrentTokens() external override view returns (address[] memory tokens) {
        return _currentTokens;
    }

    function getDenormalizedWeight(address token) external override pure returns (uint) {
        token;
        return KassandraConstants.MIN_WEIGHT;
    }

    function getTotalDenormalizedWeight() external override view returns (uint) {
        return _totalWeight;
    }

    function getNormalizedWeight(address token) external override view returns (uint) {
        return KassandraSafeMath.bdiv(_denormWeights[token], _totalWeight);
    }

    function getBalance(address token) external override view returns (uint) {
        return _balances[token];
    }

    function getSwapFee() external override pure returns (uint) {
        return 0;
    }

    function getSpotPrice(address tokenIn, address tokenOut) external pure returns (uint) {
        tokenIn;
        tokenOut;
        return 0;
    }
    function getSpotPriceSansFee(address tokenIn, address tokenOut) external pure returns (uint) {
        tokenIn;
        tokenOut;
        return 0;
    }

    function getExitFee() external override pure returns (uint) {
        return 0;
    }

    function getExitFeeCollector() public override pure returns (address) {
        return address(0);
    }
}

/**
 * @title A mocking library for easing the tests that need a CRPool
 */
contract CRPMock is IConfigurableRightsPoolDef {
    // @dev Current tokens in the pool mocked
    IPool private _corePool;
    IFactory private _coreFactory;
    SmartPoolManager.NewTokenParams public override newToken;

    /**
     * @dev Set a pool that will be returned by corePool()
     *
     * @param pool - The address of the pool contract
     */
    function mockCorePool(address pool) external {
        _corePool = IPool(pool);
    }

    /**
     * @dev Set a factory for checking $KACY
     *
     * @param factory - The address of the factory contract
     */
    function mockCoreFactory(address factory) external {
        _coreFactory = IFactory(factory);
    }

    // Just implementing the interface so tests don't take too long nor fail

    function updateWeight(address token, uint newWeight) external override pure {
        token;
        newWeight;
    }

    function updateWeightsGradually(uint[] calldata newWeights, uint startBlock, uint endBlock) external override view {
        startBlock;
        require(block.number < endBlock, "ERR_GRADUAL_UPDATE_TIME_TRAVEL");
        address[] memory tokens = _corePool.getCurrentTokens();
        require(newWeights.length == tokens.length, "ERR_START_WEIGHTS_MISMATCH");
        uint weightsSum = 0;
        uint kacyDenorm = 0;
        address kacyToken = _coreFactory.kacyToken();

        for (uint i = 0; i < newWeights.length; i++) {
            require(newWeights[i] <= KassandraConstants.MAX_WEIGHT, "ERR_WEIGHT_ABOVE_MAX");
            require(newWeights[i] >= KassandraConstants.MIN_WEIGHT, "ERR_WEIGHT_BELOW_MIN");
            weightsSum += newWeights[i];

            if (tokens[i] == kacyToken) {
                kacyDenorm = newWeights[i];
            }
        }

        require(weightsSum <= KassandraConstants.MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        require(_coreFactory.minimumKacy() <= KassandraSafeMath.bdiv(kacyDenorm, weightsSum), "ERR_MIN_KACY");
    }

    function pokeWeights() external override pure {
        return;
    }

    function commitAddToken(address token, uint balance, uint denormalizedWeight) external override {
        newToken.isCommitted = true;
        newToken.addr = token;
        newToken.commitBlock = 0;
        newToken.denorm = denormalizedWeight;
        newToken.balance = balance;
    }

    function applyAddToken() external override {
        IERC20(newToken.addr).transferFrom(msg.sender, address(this), newToken.balance);
    }

    function removeToken(address token) external override {
        SafeERC20.safeTransfer(IERC20(token), msg.sender, _corePool.getBalance(token));
    }

    function mintPoolShareFromLib(uint amount) external override pure {
        amount;
    }

    function pushPoolShareFromLib(address to, uint amount) external override pure {
        amount;
        to;
    }

    function pullPoolShareFromLib(address from, uint amount) external override pure {
        amount;
        from;
    }

    function burnPoolShareFromLib(uint amount) external override pure {
        amount;
    }

    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn) external override pure {
        poolAmountOut;
        maxAmountsIn;
    }

    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut) external override pure {
        poolAmountIn;
        minAmountsOut;
    }


    function joinswapExternAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        uint minPoolAmountOut
    )
        external pure
        returns (uint poolAmountOut)
    {
        tokenIn;
        tokenAmountIn;
        minPoolAmountOut;
        return 0;
    }

    function joinswapPoolAmountOut(
        address tokenIn,
        uint poolAmountOut,
        uint maxAmountIn
    )
        external pure
        returns (uint tokenAmountIn)
    {
        tokenIn;
        poolAmountOut;
        maxAmountIn;
        return 0;
    }

    function exitswapPoolAmountIn(
        address tokenOut,
        uint poolAmountIn,
        uint minAmountOut
    )
        external pure
        returns (uint tokenAmountOut)
    {
        tokenOut;
        poolAmountIn;
        minAmountOut;
        return 0;
    }

    function exitswapExternAmountOut(
        address tokenOut,
        uint tokenAmountOut,
        uint maxPoolAmountIn
    )
        external pure
        returns (uint poolAmountIn)
    {
        tokenOut;
        tokenAmountOut;
        maxPoolAmountIn;
        return 0;
    }

    function corePool() external override view returns(IPool) {
        return _corePool;
    }
}
