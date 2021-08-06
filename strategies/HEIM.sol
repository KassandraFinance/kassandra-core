//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@api3/airnode-protocol/contracts/AirnodeClient.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../contracts/utils/Ownable.sol";

import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";

import "../libraries/KassandraConstants.sol";
// import "../libraries/KassandraSafeMath.sol";
// import "../libraries/SmartPoolManager.sol";

/**
 * @title $HEIM strategy
 */
contract StrategyHEIM is Ownable, Pausable, AirnodeClient {
    // API3 requests limiter
    uint private constant _FINISHED = 1;
    uint private constant _ONGOING = 2;
    uint256 private _requestStatus = _FINISHED;
    // API3 data
    bytes32 public providerId;
    bytes32 public endpointId;
    uint256 public requesterInd;
    address public designatedWallet;
    address public updater;
    // list of token symbols to be requested to Heimdall
    string[] public tokensListHeimdall;
    // same as above but already encoded for API3 request
    bytes private _parametersHeimdall;
    // list of incoming responses that have been queued
    mapping(bytes32 => bool) public incomingFulfillments;

    // pool addresses
    IConfigurableRightsPool public crpPool;
    IFactory public coreFactory;

    event RequestFailed(bytes32 indexed requestId, bytes32 indexed reason);

    /**
     * @notice Construct the $HEIM Strategy
     *
     * @dev The token list is used to more easily add and remove tokens,
     *      the real parameter argument is already ABI encoded to save gas later.
     *
     * @param airnodeAddress - the address of the Airnode contract in the network
     * @param coreFactoryAddr - the core Pool Factory used to check minimum $KACY
     * @param crpPoolAddr - the CRPool address the strategy will operate
     * @param tokensList - the list of tokens, at the same order as in the pool, that will be requested to Heimdall
     */
    constructor(
        address airnodeAddress,
        address coreFactoryAddr,
        address crpPoolAddr,
        string[] memory tokensList
        )
        AirnodeClient(airnodeAddress)
    {
        coreFactory = IFactory(coreFactoryAddr);
        crpPool = IConfigurableRightsPool(crpPoolAddr);
        tokensListHeimdall = tokensList;
        _encodeParameters();
    }

    /**
     * @notice Update API3 request info
     *
     * @param providerId_ - ID of data provider
     * @param endpointId_ - ID of the endpoint for that provider
     * @param requesterInd_ - ID of the requester (governance)
     * @param designatedWallet_ - Wallet the governance allowed to use
     */
    function setApi3(
        bytes32 providerId_,
        bytes32 endpointId_,
        uint256 requesterInd_,
        address designatedWallet_
        )
        external
        onlyOwner
    {
        providerId = providerId_;
        endpointId = endpointId_;
        requesterInd = requesterInd_;
        designatedWallet = designatedWallet_;
    }

    /**
     * @notice Update pool address
     *
     * @param newAddress - Address of new crpPool
     */
    function setCrpPool(address newAddress)
        external
        onlyOwner
    {
        crpPool = IConfigurableRightsPool(newAddress);
    }

    /**
     * @notice Update core factory address
     *
     * @param newAddress - Address of new factory
     */
    function setCoreFactory(address newAddress)
        external
        onlyOwner
    {
        coreFactory = IFactory(newAddress);
    }

    /**
     * @notice The responsible to update the contract
     *
     * @param newAddress - Address of new updater
     */
    function setUpdater(address newAddress)
        external
        onlyOwner
    {
        updater = newAddress;
    }

    /**
     * @notice Schedule (commit) a token to be added; must call applyAddToken after a fixed
     *         number of blocks to actually add the token
     *
     * @dev Wraps the crpPool function to prevent the strategy updating weights while adding
     *      a token and to also update the strategy with the new token. Tokens for filling the
     *      balance should be sent to this contract so that applying the token can happen.
     *
     * @param tokenSymbol - Token symbol for Heimdall  
     *                      The token symbol can be different from the symbol in the contract
     * @param token - the token to be added
     * @param balance - how much to be added
     * @param denormalizedWeight - the desired token weight
     */
    function commitAddToken(
        string calldata tokenSymbol,
        address token,
        uint balance,
        uint denormalizedWeight
        )
        external
        onlyOwner
    {
        require(tokensListHeimdall.length < 15, "ERR_MAX_14_TOKENS");
        _pause();
        crpPool.commitAddToken(token, balance, denormalizedWeight);
        tokensListHeimdall.push(tokenSymbol);
        _encodeParameters();
    }

    /**
     * @notice Tokens should already have been sent to this contract to be sent to the Pool in this call
     *
     * @dev This will apply adding the token, anyone can call it so that the governance doesn't need to
     *      create two proposals to do the same thing. Adding the token has already been accepted.
     *      applyAddToken on crpPool locks
     */
    function applyAddToken()
        external
    {
        crpPool.applyAddToken();
        _unpause();
    }

    /**
     * @notice Remove a token from the pool
     *
     * @dev corePool is a contract interface; function calls on it are external
     *
     * @param tokenSymbol - Token symbol for Heimdall  
     *                      The token symbol can be different from the symbol in the contract
     * @param token - token to remove
     */
    function removeToken(
        string calldata tokenSymbol,
        address token
        )
        external
        onlyOwner
    {
        _pause();
        crpPool.removeToken(token);

        // similar logic to `corePool.unbind()` so the token locations match
        uint index = 200;
        uint last = tokensListHeimdall.length - 1;

        for (uint i = 0; i < tokensListHeimdall.length; i++) {
            if (keccak256(abi.encodePacked(tokensListHeimdall[i])) == keccak256(abi.encodePacked(tokenSymbol))) {
                index = i;
            }
        }

        require(index < 200, "ERR_TOKEN_SYMBOL_NOT_FOUND");

        tokensListHeimdall[index] = tokensListHeimdall[last];
        tokensListHeimdall.pop();

        // encode the new paramaters
        _encodeParameters();
    }

    /**
     * @notice Starts a request for Heimdall data through API3
     */
    function makeRequest()
        external
        whenNotPaused
    {
        require(msg.sender == updater, "ERR_NOT_UPDATER");
        // require(_requestStatus != _ONGOING, "ERR_ONLY_ONE_REQUEST_AT_TIME");
        // _requestStatus = _ONGOING;
        // SmartPoolManager.GradualUpdateParams gradualUpdate = crpPool.gradualUpdate();
        // require(block.number + 1 > gradualUpdate.endBlock, "ERR_GRADUAL_STILL_ONGOING");
        bytes32 requestId = airnode.makeFullRequest(
            providerId,             // ID of the data provider
            endpointId,             // ID for the endpoint we will request
            requesterInd,           // Requester index that allows this client to use the funds in the designated wallet
            designatedWallet,       // The designated wallet ther requester allowed this client to use
            address(this),          // address contacted when request finishes
            this.strategy.selector, // function in this contract called when request finishes
            _parametersHeimdall     // list of tokens
        );
        incomingFulfillments[requestId] = true;
    }

    /**
     * @notice Fullfill an API3 request and update the weights of the crpPool
     *
     * @dev only Airnode itself can call this function
     */
    function strategy(
        bytes32 requestId,
        uint256 statusCode,
        int256 data
        )
        external
        whenNotPaused
        onlyAirnode()
    {
        require(incomingFulfillments[requestId], "ERR_NO_SUCH_REQUEST_MADE");
        delete incomingFulfillments[requestId];
        // _requestStatus = _FINISHED;

        // Heimdall API declares that the most significative bit is always 1 if the request works
        if (statusCode == 0 && data < 0) {
            uint tokensLen = tokensListHeimdall.length;
            uint totalScore;
            uint[] memory scores;
            address[] memory tokenAddresses = IPool(crpPool.corePool()).getCurrentTokens();
            address kacyToken = coreFactory.kacyToken();
            uint kacyIdx;

            // get social scores
            for (uint i = 0; i < tokensLen; i++) {
                scores[i] = uint256(data >> (i * 18) & 0x3FFFF);
                if (scores[i] == 0x3FFFF) {
                    emit RequestFailed(requestId, "ERR_SCORE_OVERFLOW");
                    return;
                }
                totalScore += scores[i];
                if (kacyToken == tokenAddresses[i]) {
                    kacyIdx = i;
                }
            }

            uint minimumKacy = coreFactory.minimumKacy();
            uint kacyPercentage = scores[kacyIdx] * KassandraConstants.ONE / totalScore;
            uint totalWeight = 40;

            if (kacyPercentage < minimumKacy) {
                totalScore -= scores[kacyIdx];
                totalWeight = 38;
            }

            // transform social scores to de-normalised weights for CRP pool
            for (uint i = 0; i < tokensLen; i++) {
                scores[i] = (scores[i] * totalWeight * KassandraConstants.ONE) / totalScore;
            }

            if (kacyPercentage < minimumKacy) {
                scores[kacyIdx] = 2;
            }

            // adjust weights before new update
            crpPool.pokeWeights();
            crpPool.updateWeightsGradually(scores, block.number, block.number + 5700);
            return;
        }

        emit RequestFailed(requestId, "ERR_BAD_RESPONSE");
    }

    /**
     * @notice Pauses the UpdateWeightsGradually and prevents API3 requests from being made
     */
    function _pause()
        override
        internal
    {
        // update weights to current block
        crpPool.pokeWeights();
        // get current weights
        IPool corePool = crpPool.corePool();
        address[] memory tokens = corePool.getCurrentTokens();
        uint[] memory weights;

        for (uint i = 0; i < tokens.length; i++) {
            weights[i] = corePool.getDenormalizedWeight(tokens[i]);
        }

        // pause the gradual weights update
        crpPool.updateWeightsGradually(weights, block.number, block.number);
        // block API3 requests
        super._pause();
    }

    /**
     * @notice Encode the symbol lists to save gas later when doing the API3 requests
     */
    function _encodeParameters()
        internal
    {
        bytes memory symbols;

        uint tokensLen = tokensListHeimdall.length - 1;

        for (uint i = 0; i < tokensLen; i++) {
            symbols = abi.encodePacked(symbols, tokensListHeimdall[i], ",");
        }

        symbols = abi.encodePacked(symbols, tokensListHeimdall[tokensLen]);
        _parametersHeimdall = abi.encode(
            bytes32("1S"),
            bytes32("symbols"), symbols
        );
    }
}
