//SPDX-License-Identifier: GPL-3-or-later
pragma solidity ^0.8.0;

import "../CRPFactory.sol";
import "../ConfigurableRightsPool.sol";

import "../interfaces/IKassandraCommunityStore.sol";
import "../interfaces/IERC20.sol";

import "../libraries/SafeERC20.sol";
import {RightsManager} from "../libraries/RightsManager.sol";

import "../utils/Ownable.sol";
import "hardhat/console.sol";

contract FundProxy is Ownable {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public managers;

    address public coreFactory;
    address public hermesProxy;
    IKassandraCommunityStore public communityStore;
    CRPFactory public crpFactory;

    constructor(
        address communityStore_,
        address crpFactory_,
        address coreFactory_,
        address hermesProxy_
    ) {
        communityStore = IKassandraCommunityStore(communityStore_);
        crpFactory = CRPFactory(crpFactory_);
        coreFactory = coreFactory_;
        hermesProxy = hermesProxy_;
    }

    function setManager(address manager, uint256 qtFundsApproved)
        external
        onlyOwner
    {
        require(manager != address(0), "ERR_ZERO_ADDRESS");
        managers[manager] = qtFundsApproved;
    }

    function setCommunityStore(address communityStore_) external onlyOwner {
        require(communityStore_ != address(0), "ERR_ZERO_ADDRESS");
        communityStore = IKassandraCommunityStore(communityStore_);
    }

    function setCRPFactory(address crpFactory_) external onlyOwner {
        require(crpFactory_ != address(0), "ERR_ZERO_ADDRESS");
        crpFactory = CRPFactory(crpFactory_);
    }

    function setCoreFactory(address coreFactory_) external onlyOwner {
        require(coreFactory_ != address(0), "ERR_ZERO_ADDRESS");
        coreFactory = coreFactory_;
    }

    function setHermesProxy(address hermesProxy_) external onlyOwner {
        require(hermesProxy_ != address(0), "ERR_ZERO_ADDRESS");
        hermesProxy = hermesProxy_;
    }

    function newFund(
        ConfigurableRightsPool.PoolParams calldata poolParams,
        uint256 initialSupply,
        uint256 feesToManager,
        uint256 feesToRefferal,
        bool isPrivate
    ) external returns (ConfigurableRightsPool) {
        require(managers[msg.sender] > 0, "ERR_NOT_ALLOWED_TO_CREATE_FUND");
        ConfigurableRightsPool crpPool = crpFactory.newCrp(
            coreFactory,
            poolParams,
            RightsManager.Rights(true, true, true, true, true, false)
        );
        for (uint256 i = 0; i < poolParams.constituentTokens.length; i++) {
            address token = poolParams.constituentTokens[i];
            uint256 amount = poolParams.tokenBalances[i];
            require(
                communityStore.isTokenWhitelisted(token),
                "ERR_TOKEN_NOT_ALLOWED"
            );
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).safeApprove(address(crpPool), type(uint256).max);
        }
        crpPool.createPool(initialSupply);
        communityStore.setManager(
            address(crpPool),
            msg.sender,
            feesToManager,
            feesToRefferal,
            isPrivate
        );
        managers[msg.sender] -= 1;
        IERC20(crpPool).safeTransfer(msg.sender, initialSupply);
        crpPool.whitelistLiquidityProvider(hermesProxy);
        return crpPool;
    }
}
