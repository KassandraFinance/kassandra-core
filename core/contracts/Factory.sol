// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

/**
 * @summary: Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`
 */
pragma solidity 0.5.12;

import "./Pool.sol";

/**
 * @title: Pool Factory
 */
contract Factory is Bronze {
    /**
     * @notice: Every new pool gets broadcast of its creation
     *
     * @param caller: Address that created a pool
     * @param pool: Address of new Pool
     */
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    /**
     * @notice: Alert of change of controller 
     *
     * @param caller: Address that changed controller
     * @param controller: Address of the new controller
     */
    event LOG_NEW_CONTROLLER(
        address indexed caller,
        address indexed controller
    );

    /// map of all pools
    mapping(address=>bool) private _isPool;
    /// controller/admin address 
    address private _controller;

    constructor() public {
        _controller = msg.sender;
    }

    /**
     * @dev: Checks if call comes from current controller/admin
     */
    modifier onlyController() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    /**
     * @notice: Check if address is a Pool
     *
     * @param b: Address for checking
     *
     * @return: Boolean telling if address is a pool
     */
    function isPool(address b)
        external view
        returns (bool)
    {
        return _isPool[b];
    }

    /**
     * @notice: Create a new Pool
     *
     * @return: Address of new Pool contract
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
     * @notice: Get address of who can create pools from this contract
     *
     * @return: Address of the controller wallet or contract
     */
    function getController()
        external view
        returns (address)
    {
        return _controller;
    }

    /**
     * @notice: Change the controller of this contract
     * 
     * @param controller: New controller address
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
