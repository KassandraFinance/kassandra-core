// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKassandraCommunityStore {
    struct PoolInfo {
        address manager;
        uint feesToManager;
        uint feesToRefferal;
    }

    function isTokenWhitelisted(
        address token
    ) external
        returns (bool);

    function getPoolInfo(
        address poolAddress
    ) external
        returns (address manager, uint feesToManager, uint feesToRefferal);

    function setWriter(
        address writer,
        bool allowance
    ) external;

    function whitelistToken(
        address token,
        bool whitelist
    ) external;

    function setManager(
        address poolAddress,
        address poolCreator,
        uint feesToManager,
        uint feesToRefferal
    ) external;
}
