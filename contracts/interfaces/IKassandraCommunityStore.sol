// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKassandraCommunityStore {
    struct PoolInfo {
        address manager;
        uint256 feesToManager;
        uint256 feesToRefferal;
        bool isPrivate;
    }

    function setInvestor(
        address poolAddress,
        address investor,
        bool isAproved
    ) external;

    function isTokenWhitelisted(address token) external returns (bool);

    function getPoolInfo(address poolAddress)
        external
        returns (PoolInfo calldata);

    function getPrivateInvestor(address poolAddress, address investor)
        external
        returns (bool);

    function setWriter(address writer, bool allowance) external;

    function setPrivatePool(address poolAddress, bool isPrivate) external;

    function whitelistToken(address token, bool whitelist) external;

    function setManager(
        address poolAddress,
        address poolCreator,
        uint256 feesToManager,
        uint256 feesToRefferal,
        bool isPrivate
    ) external;
}
