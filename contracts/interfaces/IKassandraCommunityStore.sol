// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IKassandraCommunityStore {
    function isTokenWhitelisted(
        address token
    ) external
        returns (bool);

    function poolToManager(
        address poolAddress
    ) external
        returns (address);

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
        address poolCreator
    ) external;
}
