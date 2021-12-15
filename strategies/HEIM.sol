//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequester.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../contracts/utils/Ownable.sol";

import "../contracts/interfaces/IConfigurableRightsPool.sol";
import "../contracts/interfaces/IFactory.sol";
import "../contracts/interfaces/IPool.sol";
import "../contracts/interfaces/IStrategy.sol";

import "../contracts/libraries/KassandraConstants.sol";

/**
 * @title $HEIM strategy
 *
 * @notice There's still some centralization to remove, the worst case scenario though is that bad
 *         weights will be put, but they'll take 24h to take total effect, and by then pretty much
 *         everybody will be able to withdraw their funds from the pool.
 *
 * @dev If you have ideas on how to make this truly decentralised get in contact with us on our GitHub
 *      We are looking for truly cryptoeconomically sound ways to fix this, so hundreds of people instead
 *      of a few dozen and that make people have a reason to maintain and secure the strategy without trolling
 */
contract StrategyHEIM is IStrategy, Ownable, Pausable, RrpRequester {
    // this prevents a possible problem that while weights change their sum could potentially go beyond maximum
    uint256 private constant _MAX_TOTAL_WEIGHT = 40; // KassandraConstants.MAX_WEIGHT - 10
    uint256 private constant _MAX_TOTAL_WEIGHT_ONE = _MAX_TOTAL_WEIGHT * 10 ** 18; // KassandraConstants.ONE
    // Exactly like _DEFAULT_MIN_WEIGHT_CHANGE_BLOCK_PERIOD from ConfigurableRightsPool.sol
    uint256 private constant _CHANGE_BLOCK_PERIOD = 5700;
    // API3 requests limiter
    uint8 private constant _NONE = 1;
    uint8 private constant _ONGOING = 2;
    uint8 private constant _SUSPEND = 3;
    uint8 private _requestStatus = _NONE;

    /// How much the new normalized weight must change to trigger an automatic suspension
    int64 public suspectDiff;
    /// The social scores from the previous call
    uint24[14] private _lastScores = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    /// The social scores that are pending a review, if any
    uint24[14] private _pendingScores = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    // The pending weights already calculated by the strategy
    uint[] private _pendingWeights;
    // The API response saved for further checks
    uint256 private _apiResponse;

    /// API3 data provider id (Heimdall)
    address public airnodeId;
    /// API3 endpoint id for the data provider (30d scores)
    bytes32 public endpointId;
    /// Sponsor that allows this client to use the funds in its designated wallet (governance)
    address public sponsorAddress;
    /// Wallet the governance funds and has designated for this contract to use
    address public sponsorWallet;

    /// Responsible for pinging this contract to start the weight update
    address public updaterRole;
    /**
     * @notice Responsible for watching this contract from misbehaviour and stopping API3 or Heimdall from manipulation.
     *         Not ideal, but works for now, plans to rewrite this in a truly decentralised way are on going.
     *         More information on the contract explanation.
     *
     * @dev If you have ideas on how to make this truly decentralised get in contact with us on our GitHub
     *      We are looking for truly cryptoeconomically sound ways to fix this, so hundreds of people instead
     *      of a few dozen and that make people have a reason to maintain and secure the strategy without trolling
     */
    address public watcherRole;
    /// List of token symbols to be requested to Heimdall
    string[] private _tokensListHeimdall;
    // same as above but already encoded for API3 request
    bytes private _parametersHeimdall;

    /// CRP this contract is a strategy of
    IConfigurableRightsPool public crpPool;
    /// Core Factory contract to get $KACY enforcement details
    IFactory public coreFactory;

    /// List of incoming responses that have been queued
    mapping(bytes32 => bool) public incomingFulfillments;

    /**
     * @notice Emitted when receiving API3 data fails
     *
     * @param requestId - What request failed
     * @param reason - The reason it failed
     */
    event RequestFailed(
        bytes32 indexed requestId,
        bytes32 indexed reason
    );

    /**
     * @notice Emitted when receiving API3 data completes
     *
     * @param requestId - What request failed
     */
    event RequestCompleted(
        bytes32 indexed requestId
    );

    /**
     * @notice Emitted when the strategy has been paused
     *
     * @param caller - Who paused the strategy
     * @param reason - The reason it was paused
     */
    event StrategyPaused(
        address indexed caller,
        bytes32 indexed reason
    );

    /**
     * @notice Emitted when the strategy has been resumed/unpaused
     *
     * @param caller - Who resumed the strategy
     * @param reason - The reason it was resumed
     */
    event StrategyResumed(
        address indexed caller,
        bytes32 indexed reason
    );

    /**
     * @notice Emitted when the suspectDiff is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewSuspectDiff(
        address indexed caller,
        int64           oldValue,
        int64           newValue
    );

    /**
     * @notice Emitted when the API3 parameters have changed
     *
     * @param caller - Who made the change
     * @param oldAirnode - Previous provider address
     * @param newAirnode - New provider address
     * @param oldEndpoint - Previous endpoint ID
     * @param newEndpoint - New endpoint ID
     * @param oldSponsor - Previous sponsor address
     * @param newSponsor - New sponsor address
     * @param oldWallet - Previous designated wallet
     * @param newWallet - New designated wallet
     */
    event NewAPI3(
        address indexed caller,
        address         oldAirnode,
        address         newAirnode,
        bytes32         oldEndpoint,
        bytes32         newEndpoint,
        address         oldSponsor,
        address         newSponsor,
        address         oldWallet,
        address         newWallet
    );

    /**
     * @notice Emitted when the CRP Pool is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewCRP(
        address indexed caller,
        address         oldValue,
        address         newValue
    );

    /**
     * @notice Emitted when the coreFactory is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewFactory(
        address indexed caller,
        address         oldValue,
        address         newValue
    );

    /**
     * @notice Emitted when the updater role is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewUpdater(
        address indexed caller,
        address         oldValue,
        address         newValue
    );

    /**
     * @notice Emitted when the watcher role is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewWatcher(
        address indexed caller,
        address         oldValue,
        address         newValue
    );

    /**
     * @notice Construct the $HEIM Strategy
     *
     * @dev The token list is used to more easily add and remove tokens,
     *      the real parameter argument is already ABI encoded to save gas later.
     *
     * @param airnodeAddress - the address of the Airnode contract in the network
     * @param tokensList - the list of tokens, at the same order as in the pool, that will be requested to Heimdall
     */
    constructor(
        address airnodeAddress,
        string[] memory tokensList
        )
        RrpRequester(airnodeAddress)
    {
        _tokensListHeimdall = tokensList;
        _encodeParameters();
        suspectDiff = int64(int256(KassandraConstants.ONE));
    }

    /**
     * @notice Set how much the normalized weight must change from the previous one to automatically suspend the update
     *         The watcher is then responsible for manually checking if the request looks normal
     *         Setting a value of 100% or above effectively disables the check
     *
     * @dev This is an absolute change in basic arithmetic subtraction, e.g. from 35% to 30% it'll be 5 diff.
     *
     * @param percentage - where 10^18 is 100%
     */
    function setSuspectDiff(int64 percentage)
        external
        onlyOwner
    {
        require(percentage > 0, "ERR_NOT_POSITIVE");
        emit NewSuspectDiff(msg.sender, suspectDiff, percentage);
        suspectDiff = percentage;
    }

    /**
     * @notice Update API3 request info
     *
     * @param airnodeId_ - Address of the data provider
     * @param endpointId_ - ID of the endpoint for that provider
     * @param sponsorAddress_ - Address of the sponsor (governance)
     * @param sponsorWallet_ - Wallet the governance allowed to use
     */
    function setApi3(
        address airnodeId_,
        bytes32 endpointId_,
        address sponsorAddress_,
        address sponsorWallet_
        )
        external
        onlyOwner
    {
        require(
            airnodeId_ != address(0) && sponsorAddress_ != address(0) && sponsorWallet_ != address(0),
            "ERR_ZERO_ADDRESS"
        );
        require(endpointId_ != 0, "ERR_ZERO_ARGUMENT");
        emit NewAPI3(
            msg.sender,
            airnodeId, airnodeId_,
            endpointId, endpointId_,
            sponsorAddress, sponsorAddress_,
            sponsorWallet, sponsorWallet_
        );
        airnodeId = airnodeId_;
        endpointId = endpointId_;
        sponsorAddress = sponsorAddress_;
        sponsorWallet = sponsorWallet_;
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
        emit NewCRP(msg.sender, address(crpPool), newAddress);
        crpPool = IConfigurableRightsPool(newAddress);
        // reverts if functions does not exist
        crpPool.corePool();
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
        emit NewFactory(msg.sender, address(coreFactory), newAddress);
        coreFactory = IFactory(newAddress);
        // reverts if functions does not exist
        coreFactory.kacyToken();
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
        require(newAddress != address(0), "ERR_ZERO_ADDRESS");
        emit NewUpdater(msg.sender, updaterRole, newAddress);
        updaterRole = newAddress;
    }

    /**
     * @notice The responsible to keep an eye on the requests
     *
     * @param newAddress - Address of new updater
     */
    function setWatcher(address newAddress)
        external
        onlyOwner
    {
        require(newAddress != address(0), "ERR_ZERO_ADDRESS");
        emit NewWatcher(msg.sender, watcherRole, newAddress);
        watcherRole = newAddress;
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
     *                      e.g. wETH needs to be checked as ETH
     * @param token - Address of the token to be added
     * @param balance - How much to be added
     * @param denormalizedWeight - The desired token weight
     */
    function commitAddToken(
        string calldata tokenSymbol,
        address token,
        uint balance,
        uint denormalizedWeight
        )
        external
        onlyOwner
        whenNotPaused
    {
        require(_tokensListHeimdall.length < 14, "ERR_MAX_14_TOKENS");
        emit StrategyPaused(msg.sender, "NEW_TOKEN_COMMITTED");
        _pause();
        crpPool.commitAddToken(token, balance, denormalizedWeight);
        _tokensListHeimdall.push(tokenSymbol);
        _encodeParameters();
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
     */
    function applyAddToken()
        external
        whenPaused
    {
        crpPool.applyAddToken();
        emit StrategyResumed(msg.sender, "NEW_TOKEN_APPLIED");
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
        whenNotPaused
    {
        _pause();
        emit StrategyPaused(msg.sender, "REMOVING_TOKEN");
        crpPool.removeToken(token);

        // similar logic to `corePool.unbind()` so the token locations match
        uint index = 200;
        uint last = _tokensListHeimdall.length;
        bytes32 tknSymbol = keccak256(abi.encodePacked(tokenSymbol));

        for (uint i = 0; i < last; i++) {
            if (keccak256(abi.encodePacked(_tokensListHeimdall[i])) == tknSymbol) {
                index = i;
            }
        }

        require(index < 200, "ERR_TOKEN_SYMBOL_NOT_FOUND");

        last -= 1;
        _tokensListHeimdall[index] = _tokensListHeimdall[last];
        _lastScores[index] = _lastScores[last];
        _tokensListHeimdall.pop();
        _lastScores[last] = 0;
        _pendingScores[last] = 0;

        // encode the new paramaters
        _encodeParameters();
        _unpause();
        emit StrategyResumed(msg.sender, "REMOVED_TOKEN");
    }

    /**
     * @notice Pause the strategy from updating weights
     *         If API3/Airnode or Heimdall send dubious data the watcher can pause that
     */
    function pause()
        external
    {
        require(msg.sender == watcherRole, "ERR_NOT_WATCHER");
        emit StrategyPaused(msg.sender, "WATCHER_PAUSED");
        _pause();
    }

    /**
     * @notice Allow the updater and airnode to once again start updating weights
     *         Only the watcher can do this
     */
    function resume()
        external
    {
        require(msg.sender == watcherRole, "ERR_NOT_WATCHER");
        require(_requestStatus != _SUSPEND, "ERR_RESOLVE_SUSPENSION_FIRST");
        emit StrategyResumed(msg.sender, "WATCHER_RESUMED");
        _requestStatus = _NONE;
        _unpause();
    }

    /**
     * @notice When the strategy has automatically suspended the watcher is responsible for manually checking the data
     *         If everything looks fine they accept the new weights or reject them.
     *
     * @dev Accepting the request will trigger the updateWeightsGradually on the pool
     *
     * @param acceptRequest - Boolean indicating if the suspended data should be accepted
     */
    function resolveSuspension(bool acceptRequest)
        external
    {
        require(msg.sender == watcherRole, "ERR_NOT_WATCHER");
        require(_requestStatus == _SUSPEND, "ERR_NO_SUSPENDED_REQUEST");

        if (acceptRequest) {
            _lastScores = _pendingScores;
            // adjust weights before new update
            crpPool.pokeWeights();
            crpPool.updateWeightsGradually(_pendingWeights, block.number, block.number + _CHANGE_BLOCK_PERIOD); // 24h
            emit StrategyResumed(msg.sender, "ACCEPTED_SUSPENDED_REQUEST");
        } else {
            emit StrategyResumed(msg.sender, "REJECTED_SUSPENDED_REQUEST");
        }

        _requestStatus = _NONE;
        _unpause();
    }

    /**
     * @notice Calculates the allocations and updates the weights in the pool
     *         Anyone can call this, but only once
     *         The strategy may pause itself if the allocations go beyond what's expected
     */
    function updateWeightsGradually() // solhint-disable function-max-lines
        external
        whenNotPaused
    {
        require(_apiResponse != 0, "ERR_NO_PENDING_DATA");

        address[] memory tokenAddresses = IPool(crpPool.corePool()).getCurrentTokens();
        uint tokensLen = tokenAddresses.length;
        uint totalPendingScore; // the total social score will be needed for transforming them to denorm weights
        uint totalLastScore; // the total social score will be needed for transforming them to denorm weights
        uint[] memory socialScores = new uint[](tokensLen);
        // we need to make sure the amount of $KACY meets the criteria specified by the protocol
        address kacyToken = coreFactory.kacyToken();
        uint kacyIdx;
        bool suspectRequest = false;

        // get social scores
        for (uint i = 0; i < tokensLen; i++) {
            if (kacyToken == tokenAddresses[i]) {
                kacyIdx = i;
                // $KACY is fixed
                continue;
            }

            /*
             * Heimdall API provides this endpoint for their Airnode so that up to 14 tokens can be checked
             * on a single request for gas savings. According to their documentation each coin uses 18 bits
             * for their social score starting from the least significant bit. 0x3FFFF is all 18 bits true
             *
             * https://api.heimdall.land/v2/docs#/social%20score/symbols_score_uint256_v2_coins_scores_post
             */
            uint socialScore = _apiResponse >> (i * 18) & 0x3FFFF;
            _pendingScores[i] = uint24(socialScore);
            socialScores[i] = socialScore;

            // if all bits are true then the number has overflown and we should ignore the response (see Heimdall docs)
            // also fail if data is missing
            require(socialScore != 0x3FFFF, "ERR_SCORE_OVERFLOW");
            require(socialScore != 0, "ERR_SCORE_ZERO");

            totalPendingScore += socialScore;
            totalLastScore += uint256(_lastScores[i]);
        }

        if (totalLastScore == 0) {
            totalLastScore = 1;
        }

        uint minimumKacy = coreFactory.minimumKacy();
        uint totalWeight = _MAX_TOTAL_WEIGHT_ONE;
        // doesn't overflow because this is always below 10^37
        uint minimumWeight = _MAX_TOTAL_WEIGHT * minimumKacy; // totalWeight * minimumKacy / KassandraConstants.ONE

        totalWeight -= minimumWeight;
        delete _apiResponse;

        for (uint i = 0; i < tokensLen; i++) {
            uint percentage95 = 95 * KassandraConstants.ONE / 100;
            uint normalizedPending = (socialScores[i] * percentage95) / totalPendingScore;
            uint normalizedLast = (_lastScores[i] * percentage95) / totalLastScore;
            // these are normalised to 10^18, so definitely won't overflow
            int64 diff = int64(int256(normalizedPending) - int256(normalizedLast));
            suspectRequest = suspectRequest || diff >= suspectDiff || diff <= -suspectDiff;

            // transform social scores to de-normalized weights for CRP pool
            socialScores[i] = (socialScores[i] * totalWeight) / totalPendingScore;
        }

        socialScores[kacyIdx] = minimumWeight;

        if (!suspectRequest) {
            _lastScores = _pendingScores;
            // adjust weights before new update
            crpPool.pokeWeights();
            crpPool.updateWeightsGradually(socialScores, block.number, block.number + _CHANGE_BLOCK_PERIOD); // 24h
            return;
        }

        _pendingWeights = socialScores;
        _requestStatus = _SUSPEND;
        super._pause();
        emit StrategyPaused(msg.sender, "ERR_SUSPECT_REQUEST");
    }

    /**
     * @notice Starts a request for Heimdall data through API3
     *         Only the allowed updater can call it
     */
    function makeRequest()
        external
        override
        whenNotPaused
    {
        require(msg.sender == updaterRole, "ERR_NOT_UPDATER");
        require(_requestStatus == _NONE, "ERR_ONLY_ONE_REQUEST_AT_TIME");
        _requestStatus = _ONGOING;
        // GradualUpdateParams gradualUpdate = crpPool.gradualUpdate();
        // require(block.number + 1 > gradualUpdate.endBlock, "ERR_GRADUAL_STILL_ONGOING");
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnodeId,             // Address of the data provider
            endpointId,             // ID for the endpoint we will request
            sponsorAddress,           // Sponsor that allows this client to use the funds in the designated wallet
            sponsorWallet,       // The designated wallet the sponsor allowed this client to use
            address(this),          // address contacted when request finishes
            this.strategy.selector, // function in this contract called when request finishes
            _parametersHeimdall     // list of tokens
        );
        incomingFulfillments[requestId] = true;
    }

    /**
     * @notice Fullfill an API3 request and update the weights of the crpPool
     *
     * @dev Only Airnode itself can call this function
     *
     * @param requestId - Request ID, to ensure it's the request we sent
     * @param statusCode - Whether the request was successfull
     * @param data - The response data from Heimdall
     */
    function strategy(
        bytes32 requestId,
        uint256 statusCode,
        int256 data
        )
        external
        override
        onlyAirnodeRrp()
    {
        require(incomingFulfillments[requestId], "ERR_NO_SUCH_REQUEST_MADE");
        delete incomingFulfillments[requestId];

        if (paused()) {
            emit RequestFailed(requestId, "ERR_STRATEGY_PAUSED");
            return;
        }

        _requestStatus = _NONE; // allow requests again

        // Heimdall API declares that the most significant bit is always 1 if the request works
        if (statusCode != 0 || data >= 0) {
            emit RequestFailed(requestId, "ERR_BAD_RESPONSE");
            return;
        }

        _apiResponse = uint256(data);
        emit RequestCompleted(requestId);
    }

    /**
     * @notice The last social scores obtained from the previous call
     *
     * @return 14 numbers; anything above the number of tokens is ignored
     */
    function lastScores() external view returns(uint24[14] memory) {
        return _lastScores;
    }

    /**
     * @notice The pending suspect social score from a suspicious call, if any
     *
     * @return 14 numbers; anything above the number of tokens is ignored
     */
    function pendingScores() external view returns(uint24[14] memory) {
        if(_requestStatus == _SUSPEND) {
            return _pendingScores;
        }
        return [uint24(0), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }

    /**
     * @notice The list of tokens to be called from Heimdall
     *
     * @return A list of token symbols to be checked against Heimdall
     */
    function tokensSymbols() external view returns(string[] memory) {
        return _tokensListHeimdall;
    }

    /**
     * @dev Pauses the UpdateWeightsGradually and prevents API3 requests from being made
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
        uint[] memory weights = new uint[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            weights[i] = corePool.getDenormalizedWeight(tokens[i]);
        }

        // pause the gradual weights update
        crpPool.updateWeightsGradually(weights, block.number, block.number + _CHANGE_BLOCK_PERIOD);
        // block API3 requests
        super._pause();
    }

    /**
     * @dev Encode the symbol lists to save gas later when doing the API3 requests
     */
    function _encodeParameters()
        internal
    {
        bytes memory symbols;

        uint tokensLen = _tokensListHeimdall.length - 1;

        for (uint i = 0; i < tokensLen; i++) {
            symbols = abi.encodePacked(symbols, _tokensListHeimdall[i], ",");
        }

        symbols = abi.encodePacked(symbols, _tokensListHeimdall[tokensLen]);
        _parametersHeimdall = abi.encode(
            bytes32("1bS"),
            bytes32("period"), bytes32("30d"),
            bytes32("symbols"), symbols
        );
    }
}
