// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./Math.sol";

import "../Token.sol";

import "../utils/Ownable.sol";
import "../utils/ReentrancyGuard.sol";

import "../../interfaces/IERC20.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IPool.sol";

import "../../libraries/KassandraConstants.sol";
import "../../libraries/KassandraSafeMath.sol";

contract Pool is IPoolDef, Ownable, ReentrancyGuard, CPToken, Math {
    struct Record {
        bool bound;   // is token bound to pool
        uint index;   // private
        uint denorm;  // denormalized weight
        uint balance;
    }

    address private _factory;    // Factory address to push token exitFee to
    bool private _publicSwap; // true if PUBLIC can call SWAP functions

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint private _swapFee;
    bool private _finalized;

    address[] private _tokens;
    mapping(address=>Record) private _records;
    uint private _totalWeight;

    event NewSwapFee(
        address indexed pool,
        address indexed caller,
        uint256 newFee
    );

    event LogSwap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
    );

    event LogJoin(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    event LogExit(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    event LogCall(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    constructor(string memory tokenSymbol, string memory tokenName)
        CPToken(tokenSymbol, tokenName)
    {
        _factory = msg.sender;
        _swapFee = KassandraConstants.MIN_FEE;
        _publicSwap = false;
        _finalized = false;
    }

    function setSwapFee(uint swapFee)
        external override
        lock
        _logs_
        onlyOwner
    {
        require(!_finalized, "ERR_IS_FINALIZED");
        require(swapFee >= KassandraConstants.MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= KassandraConstants.MAX_FEE, "ERR_MAX_FEE");
        emit NewSwapFee(address(this), msg.sender, swapFee);
        _swapFee = swapFee;
    }

    function setPublicSwap(bool public_)
        external override
        lock
        _logs_
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

    function finalize()
        external
        lock
        _logs_
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

        _mintPoolShare(KassandraConstants.INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, KassandraConstants.INIT_POOL_SUPPLY);
    }

    function bind(address token, uint balance, uint denorm)
        external override
        _logs_
        onlyOwner
        // lock  Bind does not lock because it jumps to `rebind`, which does
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

    function unbind(address token)
        external override
        lock
        _logs_
        onlyOwner
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_finalized, "ERR_IS_FINALIZED");
        // can't remove kacy
        IFactory factory = IFactory(_factory);
        require(token != factory.kacyToken(), "ERR_MIN_KACY");

        uint tokenBalance = _records[token].balance;

        _totalWeight -= _records[token].denorm;

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

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token)
        external
        lock
        _logs_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external
        lock
        _logs_
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

    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external
        lock
        _logs_
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

    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external
        lock
        _logs_
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

    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external
        lock
        _logs_
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

    function joinswapExternAmountIn(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external
        lock
        _logs_
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

    function joinswapPoolAmountOut(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external
        lock
        _logs_
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

    function exitswapPoolAmountIn(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external
        lock
        _logs_
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

    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external
        lock
        _logs_
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

    function isPublicSwap()
        external view override
        returns (bool)
    {
        return _publicSwap;
    }

    function isFinalized()
        external view
        returns (bool)
    {
        return _finalized;
    }

    function isBound(address t)
        external view override
        returns (bool)
    {
        return _records[t].bound;
    }

    function getNumTokens()
        external view
        returns (uint)
    {
        return _tokens.length;
    }

    function getCurrentTokens()
        external view override viewlock
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getFinalTokens()
        external view
        viewlock
        returns (address[] memory tokens)
    {
        require(_finalized, "ERR_NOT_FINALIZED");
        return _tokens;
    }

    function getDenormalizedWeight(address token)
        external view override
        viewlock
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external view override
        viewlock
        returns (uint)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
        external view override
        viewlock
        returns (uint)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        uint denorm = _records[token].denorm;
        return KassandraSafeMath.bdiv(denorm, _totalWeight);
    }

    function getBalance(address token)
        external view override
        viewlock
        returns (uint)
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee()
        external view override
        viewlock
        returns (uint)
    {
        return _swapFee;
    }

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

    function rebind(address token, uint balance, uint denorm)
        public override
        lock
        _logs_
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
        } else if (denorm < oldWeight) {
            _totalWeight -= oldWeight - denorm;
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

    function _pullUnderlying(address erc20, address from, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint amount)
        internal
    {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint amount)
        internal
    {
        _push(to, amount);
    }

    function _mintPoolShare(uint amount)
        internal
    {
        _mint(amount);
    }

    function _burnPoolShare(uint amount)
        internal
    {
        _burn(amount);
    }
}
