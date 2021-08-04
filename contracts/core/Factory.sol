// SPDX-License-Identifier: GPL-3.0-or-later
/**
 * @summary Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`
 */
pragma solidity ^0.8.0;

import "./Pool.sol";

import "../utils/Ownable.sol";

import "../../interfaces/IcrpFactory.sol";

import "../../libraries/KassandraConstants.sol";

/**
 * @title Pool Factory
 */
contract Factory is Ownable {
    // the CRPFactory contract allowed to create pools
    IcrpFactory public crpFactory;
    // $KACY enforcement
    address public kacyToken;
    uint public minimumKacy;
    // map of all pools
    mapping(address=>bool) private _isPool;

    /**
     * @notice Every new pool gets broadcast of its creation
     *
     * @param caller - Address that created a pool
     * @param pool - Address of new Pool
     */
    event LogNewPool(
        address indexed caller,
        address indexed pool
    );

    /**
     * @notice Create a new Pool
     *
     * @return pool - Address of new Pool contract
     */
    function newPool()
        external
        returns (Pool pool)
    {
        // only the governance or the CRP pools can request to create core pools
        require(msg.sender == this.getController() || crpFactory.isCrp(msg.sender), "ERR_NOT_CONTROLLER");

        pool = new Pool();
        _isPool[address(pool)] = true;
        emit LogNewPool(msg.sender, address(pool));
        pool.setController(msg.sender);
    }

    /**
     * @notice Collect fees generated from exits
     *
     * @dev When someone exists a pool the fees are collected here
     *
     * @param pool - The address of the Pool token that will be collected
     */
    function collect(Pool pool)
        external onlyOwner
    {
        uint collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(this.getController(), collected);
        require(xfer, "ERR_ERC20_FAILED");
    }

    /**
     * @notice Set address of CRPFactory
     *
     * @dev This address is used to allow CRPPools to create Pools as well
     *
     * @param factoryAddr - Address of the CRPFactory
     */
    function setCRPFactory(address factoryAddr)
        external onlyOwner
    {
        crpFactory = IcrpFactory(factoryAddr);
    }

    /**
     * @notice Set who's the $KACY token
     *
     * @param newAddr - Address of a valid EIP-20 token
     */
    function setKacyToken(address newAddr)
        external onlyOwner
    {
        kacyToken = newAddr;
    }

    /**
     * @notice Set the minimum percentage of $KACY a pool needs
     *
     * @param percent - how much of $KACY a pool requires
     */
    function setKacyMinimum(uint percent)
        external onlyOwner
    {
        require(percent < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        minimumKacy = percent;
    }

    /**
     * @notice Check if address is a Pool
     *
     * @param b Address for checking
     *
     * @return Boolean telling if address is a pool
     */
    function isPool(address b)
        external view
        returns (bool)
    {
        return _isPool[b];
    }
}
