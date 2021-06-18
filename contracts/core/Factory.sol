// SPDX-License-Identifier: GPL-3.0-or-later
/**
 * @summary Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`
 */
pragma solidity ^0.8.0;

import "./Pool.sol";

/**
 * @title Pool Factory
 */
contract Factory {
    /**
     * @dev Every new pool gets broadcast of its creation
     *
     * @param caller Address that created a pool
     * @param pool Address of new Pool
     */
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    /**
     * @dev Alert of change of controller
     *
     * @param caller Address that changed controller
     * @param controller Address of the new controller
     */
    event LOG_NEW_CONTROLLER(
        address indexed caller,
        address indexed controller
    );

    // map of all pools
    mapping(address=>bool) private _isPool;
    // controller/admin address
    address private _controller;

    constructor() {
        _controller = msg.sender;
    }

    /**
     * @dev Checks if call comes from current controller/admin
     */
    modifier onlyController() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
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

    /**
     * @dev Create a new Pool
     *
     * @return Address of new Pool contract
     */
    function newPool()
        external onlyController
        returns (Pool)
    {
        Pool pool = new Pool();
        _isPool[address(pool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(pool));
        pool.setController(msg.sender);
        return pool;
    }

    /**
     * @dev Get address of who can create pools from this contract
     *
     * @return Address of the controller wallet or contract
     */
    function getController()
        external view
        returns (address)
    {
        return _controller;
    }

    /**
     * @dev Change the controller of this contract
     *
     * @param controller New controller address
     */
    function setController(address controller)
        external onlyController
    {
        emit LOG_NEW_CONTROLLER(msg.sender, controller);
        _controller = controller;
    }

    function collect(Pool pool)
        external onlyController
    {
        uint collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(_controller, collected);
        require(xfer, "ERR_ERC20_FAILED");
    }
}
