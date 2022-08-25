// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";

import "../interfaces/IKassandraCommunityStore.sol";

contract KassandraCommunityStore is IKassandraCommunityStore, Ownable {
    mapping(address => bool) private _writers;

    mapping(address => bool) public isTokenWhitelisted;
    mapping(address => PoolInfo) private _poolInfo;

    function setWriter(address writer, bool allowance) public onlyOwner {
        require(writer != address(0), "ERR_WRITER_ADDRESS_ZERO");
        _writers[writer] = allowance;
    }

    function whitelistToken(address token, bool whitelist) public onlyOwner {
        require(token != address(0), "ERR_TOKEN_ADDRESS_ZERO");
        isTokenWhitelisted[token] = whitelist;
    }

    function setManager(
        address poolAddress,
        address poolCreator,
        uint256 feesToManager,
        uint256 feesToRefferal
    ) public {
        require(poolAddress != address(0), "ERR_POOL_ADDRESS_ZERO");
        require(poolCreator != address(0), "ERR_MANAGER_ADDRESS_ZERO");
        require(_writers[msg.sender], "ERR_NOT_ALLOWED_WRITER");
        _poolInfo[poolAddress].manager = poolCreator;
        _poolInfo[poolAddress].feesToManager = feesToManager;
        _poolInfo[poolAddress].feesToRefferal = feesToRefferal;
    }

    function getPoolInfo(address poolAddress)
        public
        view
        returns (
            address manager,
            uint256 feesToManager,
            uint256 feesToRefferal
        )
    {
        manager = _poolInfo[poolAddress].manager;
        feesToManager = _poolInfo[poolAddress].feesToManager;
        feesToRefferal = _poolInfo[poolAddress].feesToRefferal;
    }
}
