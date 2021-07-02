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
     * @dev Every new pool gets broadcast of its creation
     *
     * @param caller Address that created a pool
     * @param pool Address of new Pool
     */
    event LogNewPool(
        address indexed caller,
        address indexed pool
    );

    /**
     * @dev Alert of change of controller
     *
     * @param caller Address that changed controller
     * @param controller Address of the new controller
     */
    event LogNewController(
        address indexed caller,
        address indexed controller
    );

    /**
     * @dev Create a new Pool
     *
     * @return pool Address of new Pool contract
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

    function collect(Pool pool)
        external onlyOwner
    {
        uint collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(this.getController(), collected);
        require(xfer, "ERR_ERC20_FAILED");
    }

    function setFactory(address factoryAddr)
        external onlyOwner
    {
        crpFactory = IcrpFactory(factoryAddr);
    }

    function setKacyToken(address newAddr)
        external onlyOwner
    {
        kacyToken = newAddr;
    }

    function setKacyMinimum(uint percent)
        external onlyOwner
    {
        require(percent < KassandraConstants.ONE, "ERR_NOT_VALID_PERCENTAGE");
        minimumKacy = percent;
    }

    /**
     * @dev Check if address is a Pool
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
