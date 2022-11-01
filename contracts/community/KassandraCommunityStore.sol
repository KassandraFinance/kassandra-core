// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../utils/Ownable.sol";

import "../interfaces/IKassandraCommunityStore.sol";

contract KassandraCommunityStore is IKassandraCommunityStore, Ownable {
    mapping(address => bool) private _writers;

    mapping(address => bool) public override isTokenWhitelisted;
    mapping(address => PoolInfo) private _poolInfo;
    mapping(address => mapping(address => bool)) private _privateInvestors;

    function setInvestor(
        address poolAddress,
        address investor,
        bool isApproved
    ) external override {
        require(_writers[msg.sender], "ERR_NOT_ALLOWED_WRITER");
        _privateInvestors[poolAddress][investor] = isApproved;
    }

    function setWriter(address writer, bool allowance)
        external
        override
        onlyOwner
    {
        require(writer != address(0), "ERR_WRITER_ADDRESS_ZERO");
        _writers[writer] = allowance;
    }

    function whitelistToken(address token, bool whitelist)
        external
        override
        onlyOwner
    {
        require(token != address(0), "ERR_TOKEN_ADDRESS_ZERO");
        isTokenWhitelisted[token] = whitelist;
    }

    function setManager(
        address poolAddress,
        address poolCreator,
        uint256 feesToManager,
        uint256 feesToReferral,
        bool isPrivate
    ) external override {
        require(poolAddress != address(0), "ERR_POOL_ADDRESS_ZERO");
        require(poolCreator != address(0), "ERR_MANAGER_ADDRESS_ZERO");
        require(_writers[msg.sender], "ERR_NOT_ALLOWED_WRITER");
        _poolInfo[poolAddress].manager = poolCreator;
        _poolInfo[poolAddress].feesToManager = feesToManager;
        _poolInfo[poolAddress].feesToReferral = feesToReferral;
        _poolInfo[poolAddress].isPrivate = isPrivate;
    }

    function setPrivatePool(address poolAddress, bool isPrivate) external override {
        require(_writers[msg.sender], "ERR_NOT_ALLOWED_WRITER");
        _poolInfo[poolAddress].isPrivate = isPrivate;
    }

    function getPoolInfo(address poolAddress)
        external
        view
        override
        returns (PoolInfo memory)
    {
        return _poolInfo[poolAddress];
    }

    function getPrivateInvestor(address poolAddress, address investor)
        external
        view
        override
        returns (bool)
    {
        return _privateInvestors[poolAddress][investor];
    }
}
