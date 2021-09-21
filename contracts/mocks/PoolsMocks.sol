//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "../libraries/KassandraConstants.sol";
import "../libraries/KassandraSafeMath.sol";

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

    function bind(address token, uint balance, uint denorm) external override pure {
        token;
        balance;
        denorm;
        return;
    }

    function unbind(address token) external override pure {
        token;
        return;
    }

    function rebind(address token, uint balance, uint denorm) external override pure {
        token;
        balance;
        denorm;
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

    function getTotalDenormalizedWeight() external override pure returns (uint) {
        return 0;
    }

    function getNormalizedWeight(address token) external override pure returns (uint) {
        token;
        return 0;
    }

    function getBalance(address token) external override pure returns (uint) {
        token;
        return 0;
    }

    function getSwapFee() external override pure returns (uint) {
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
        return;
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

    function commitAddToken(address token, uint balance, uint denormalizedWeight) external override pure {
        token;
        balance;
        denormalizedWeight;
        return;
    }

    function applyAddToken() external override pure {
        return;
    }

    function removeToken(address token) external override pure {
        token;
        return;
    }

    function mintPoolShareFromLib(uint amount) external override pure {
        amount;
        return;
    }

    function pushPoolShareFromLib(address to, uint amount) external override pure {
        amount;
        to;
        return;
    }

    function pullPoolShareFromLib(address from, uint amount) external override pure {
        amount;
        from;
        return;
    }

    function burnPoolShareFromLib(uint amount) external override pure {
        amount;
        return;
    }


    function corePool() external override view returns(IPool) {
        return _corePool;
    }
}
