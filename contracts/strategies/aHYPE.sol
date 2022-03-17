//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequester.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "../utils/Ownable.sol";

import "../interfaces/IConfigurableRightsPool.sol";
import "../interfaces/IFactory.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IStrategy.sol";

import "../libraries/KassandraConstants.sol";

/**
 * @title $aHYPE strategy
 *
 * @notice There's still some centralization to remove, the worst case scenario though is that bad
 *         weights will be put, but they'll take 24h to take total effect, and by then pretty much
 *         everybody will be able to withdraw their funds from the pool.
 *
 * @dev If you have ideas on how to make this truly decentralised get in contact with us on our GitHub
 *      We are looking for truly cryptoeconomically sound ways to fix this, so hundreds of people instead
 *      of a few dozen and that make people have a reason to maintain and secure the strategy without trolling
 */
contract StrategyAHYPE is IStrategy, Ownable, Pausable, RrpRequester {
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
    bool private _hasAPIData;

    /// How much the new normalized weight must change to trigger an automatic suspension
    int64 public suspectDiff;
    /// The social scores from the previous call
    uint24[16] private _lastScores;
    /// The social scores that are pending a review, if any
    uint24[16] private _pendingScores;
    // The pending weights already calculated by the strategy
    uint256[] private _pendingWeights;

    /// Amount of blocks weights will update linearly
    uint256 public weightUpdateBlockPeriod;

    /// API3 data provider id (Heimdall)
    address public airnodeId;
    /// API3 endpoint id for the data provider (30d scores)
    bytes32 public endpointId;
    /// API3 template id where request is already cached
    bytes32 public templateId;
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

    /// CRP this contract is a strategy of
    IConfigurableRightsPool public crpPool;
    /// Core Factory contract to get $KACY enforcement details
    IFactory public coreFactory;

    /// List of incoming responses that have been queued
    mapping(bytes32 => bool) public incomingFulfillments;

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
     * @notice Emitted when the block period for weight update is changed
     *
     * @param caller - Who made the change
     * @param oldValue - Previous value
     * @param newValue - New value
     */
    event NewBlockPeriod(
        address indexed caller,
        uint256         oldValue,
        uint256         newValue
    );

    /**
     * @notice Construct the $aHYPE Strategy
     *
     * @dev The token list is used to more easily add and remove tokens,
     *      the real parameter argument is already ABI encoded to save gas later.
     *
     * @param airnodeAddress - the address of the Airnode contract in the network
     * @param tokensList - the list of tokens, at the same order as in the pool, that will be requested to Heimdall
     */
    constructor(
        address airnodeAddress,
        uint weightBlockPeriod,
        string[] memory tokensList
        )
        RrpRequester(airnodeAddress)
    {
        require(weightBlockPeriod >= _CHANGE_BLOCK_PERIOD, "ERR_BELOW_MINIMUM");
        require(tokensList.length >= KassandraConstants.MIN_ASSET_LIMIT, "ERR_TOO_FEW_TOKENS");
        require(tokensList.length <= KassandraConstants.MAX_ASSET_LIMIT, "ERR_TOO_MANY_TOKENS");
        weightUpdateBlockPeriod = weightBlockPeriod;
        _tokensListHeimdall = tokensList;
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
        _encodeParameters();
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
     * @notice Update block period for weight updates
     *
     * @param newPeriod - Period in blocks the weights will update
     */
    function setWeightUpdateBlockPeriod(uint newPeriod)
        external
        onlyOwner
    {
        require(newPeriod >= _CHANGE_BLOCK_PERIOD, "ERR_BELOW_MINIMUM");
        emit NewBlockPeriod(msg.sender, weightUpdateBlockPeriod, newPeriod);
        weightUpdateBlockPeriod = newPeriod;
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
        require(_tokensListHeimdall.length < 16, "ERR_MAX_16_TOKENS");
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
     * @notice A soft version of `resume`, allows the updater and airnode to
     *         once again start updating weights. This version only resolves
     *         the case where an API call failed and the contracts remains
     *         waiting for the call to return.
     *
     *         Only the watcher can do this
     *
     *         This is a security measure to prevent the Airnode from creating
     *         a rogue request in the future using an old failed ID.
     *
     * @param requestId - ID for the request that failed but is still saved
     */
    function clearFailedRequest(bytes32 requestId)
        external
    {
        require(msg.sender == watcherRole, "ERR_NOT_WATCHER");
        require(_requestStatus != _SUSPEND, "ERR_RESOLVE_SUSPENSION_FIRST");
        delete incomingFulfillments[requestId];
        _requestStatus = _NONE;
        _hasAPIData = false;
        emit StrategyResumed(msg.sender, "WATCHER_CLEARED_FAILED_REQUEST");
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
            crpPool.updateWeightsGradually(_pendingWeights, block.number, block.number + weightUpdateBlockPeriod);
            emit StrategyResumed(msg.sender, "ACCEPTED_SUSPENDED_REQUEST");
        } else {
            emit StrategyResumed(msg.sender, "REJECTED_SUSPENDED_REQUEST");
        }

        delete _pendingScores;
        _requestStatus = _NONE;
        _unpause();
    }

    /**
     * @notice Calculates the allocations and updates the weights in the pool
     *         Anyone can call this, but only once
     *         The strategy may pause itself if the allocations go beyond what's expected
     */
    function updateWeightsGradually()
        external whenNotPaused
    {
        require(_hasAPIData, "ERR_NO_PENDING_DATA");
        _hasAPIData = false;
        address[] memory tokenAddresses = IPool(crpPool.corePool()).getCurrentTokens();
        uint tokensLen = tokenAddresses.length;
        uint totalPendingScore; // the total social score will be needed for transforming them to denorm weights
        uint totalLastScore; // the total social score will be needed for transforming them to denorm weights
        uint[] memory tokenWeights = new uint[](tokensLen);
        // we need to make sure the amount of $KACY meets the criteria specified by the protocol
        address kacyToken = coreFactory.kacyToken();
        uint kacyIdx;
        bool suspectRequest = false;

        // get social scores
        for (uint i = 0; i < tokensLen; i++) {
            if (kacyToken == tokenAddresses[i]) {
                kacyIdx = i;
                continue; // $KACY is fixed
            }

            require(_pendingScores[i] != 0, "ERR_SCORE_ZERO");
            totalPendingScore += _pendingScores[i];
            totalLastScore += uint256(_lastScores[i]);
        }

        if (totalLastScore == 0) {totalLastScore = 1;}

        uint minimumKacy = coreFactory.minimumKacy();
        uint totalWeight = _MAX_TOTAL_WEIGHT_ONE;
        // doesn't overflow because this is always below 10^37
        uint minimumWeight = _MAX_TOTAL_WEIGHT * minimumKacy; // totalWeight * minimumKacy / KassandraConstants.ONE
        totalWeight -= minimumWeight;

        for (uint i = 0; i < tokensLen; i++) {
            uint percentage95 = 95 * KassandraConstants.ONE / 100;
            uint normalizedPending = (_pendingScores[i] * percentage95) / totalPendingScore;
            uint normalizedLast = (_lastScores[i] * percentage95) / totalLastScore;
            // these are normalised to 10^18, so definitely won't overflow
            int64 diff = int64(int256(normalizedPending) - int256(normalizedLast));
            suspectRequest = suspectRequest || diff >= suspectDiff || diff <= -suspectDiff;
            // transform social scores to de-normalized weights for CRP pool
            tokenWeights[i] = (_pendingScores[i] * totalWeight) / totalPendingScore;
        }

        tokenWeights[kacyIdx] = minimumWeight;

        if (!suspectRequest) {
            _lastScores = _pendingScores;
            delete _pendingScores;
            // adjust weights before new update
            crpPool.pokeWeights();
            crpPool.updateWeightsGradually(tokenWeights, block.number, block.number + weightUpdateBlockPeriod);
            return;
        }

        _pendingWeights = tokenWeights;
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
        bytes32 requestId = airnodeRrp.makeTemplateRequest(
            templateId,             // Address of the data provider
            sponsorAddress,         // Sponsor that allows this client to use the funds in the designated wallet
            sponsorWallet,          // The designated wallet the sponsor allowed this client to use
            address(this),          // address contacted when request finishes
            this.strategy.selector, // function in this contract called when request finishes
            ""                      // extra parameters, that we don't need
        );
        incomingFulfillments[requestId] = true;
    }

    /**
     * @notice Fullfill an API3 request and update the weights of the crpPool
     *
     * @dev Only Airnode itself can call this function
     *
     * @param requestId - Request ID, to ensure it's the request we sent
     * @param response - The response data from Heimdall
     */
    function strategy(
        bytes32 requestId,
        bytes calldata response
        )
        external
        override
        whenNotPaused
        onlyAirnodeRrp()
    {
        require(incomingFulfillments[requestId], "ERR_NO_SUCH_REQUEST_MADE");
        delete incomingFulfillments[requestId];

        _hasAPIData = true;
        _requestStatus = _NONE; // allow requests again

        uint24[] memory data = abi.decode(response, (uint24[]));

        for (uint i = 0; i < data.length - 1; i++) {
            _pendingScores[i] = data[i];
        }

        emit RequestCompleted(requestId);
    }

    /**
     * @notice The last social scores obtained from the previous call
     *
     * @return 16 numbers; anything above the number of tokens is ignored
     */
    function lastScores() external view returns(uint24[16] memory) {
        return _lastScores;
    }

    /**
     * @notice The pending suspect social score from a suspicious call, if any
     *
     * @return 16 numbers; anything above the number of tokens is ignored
     */
    function pendingScores() external view returns(uint24[16] memory) {
        return _pendingScores;
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

        templateId = airnodeRrp.createTemplate(
            airnodeId,
            endpointId,
            abi.encode(
                bytes32("1sS"),
                bytes32("period"), bytes32("30d"),
                bytes32("symbols"), symbols
            )
        );
    }
}
