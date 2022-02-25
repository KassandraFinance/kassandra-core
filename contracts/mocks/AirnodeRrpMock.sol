//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "../interfaces/IStrategy.sol";

/**
 * @title This is a mock of the API3 Airnode for testing the strategy
 */
contract AirnodeRrpMock {
    /// @dev Address of the strategy contract
    IStrategy public strategy;
    /// @dev For checking the makeTemplateRequest was successful
    bytes32 public lastRequestId;

    /**
     * @dev For checking if the strategy made the request correctly
     */
    function makeTemplateRequest(
        bytes32 templateId,
        address sponsor,
        address sponsorWallet,
        address fulfillAddress,
        bytes4 fulfillFunctionId,
        bytes calldata parameters
    ) external returns (bytes32 requestId) {
        requestId = keccak256(abi.encode(
            templateId,
            sponsor,
            sponsorWallet,
            fulfillAddress,
            fulfillFunctionId,
            parameters
        ));
        lastRequestId = requestId;
    }

    /**
     * @dev Set the address of the strategy contract for calling it in the tests
     *
     * @param addr - Address of teh strategy contract to be tested
     */
    function setStrategyAddress(address addr) external {
        strategy = IStrategy(addr);
    }

    /**
     * @dev For testing the main strategy function.
     */
    function callStrategy(
        bytes32 requestId,
        bytes calldata response
        )
        external
    {
        strategy.strategy(requestId, response);
    }

    /**
     * @dev To allow the tests to work
     */
    function createTemplate(
        address,
        bytes32,
        bytes calldata
    ) external pure returns (bytes32) {
        return "";
    }

    function setSponsorshipStatus(address, bool) external pure {
        return;
    }
}
