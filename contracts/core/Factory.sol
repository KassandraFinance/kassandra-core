// SPDX-License-Identifier: GPL-3.0-or-later
/**
 * @summary Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`
 */
pragma solidity ^0.8.0;

import "./Pool.sol";

import "../utils/Ownable.sol";

import "../../interfaces/IERC20.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IcrpFactory.sol";

import "../../libraries/KassandraConstants.sol";
import "../../libraries/SmartPoolManager.sol";

/**
 * @title Pool Factory
 */
contract Factory is IFactoryDef, Ownable {
    // the CRPFactory contract allowed to create pools
    IcrpFactory public crpFactory;
    // $KACY enforcement
    address public override kacyToken;
    uint public override minimumKacy;
    // map of all pools
    mapping(address=>bool) private _isPool;

    /**
     * @notice If the minimum amount of $KACY is changed
     *
     * @param caller - Address that changed minimum
     * @param percentage - the new minimum percentage
     */
    event NewMinimum(
        address indexed caller,
        uint256 percentage
    );

    /**
     * @notice If the token being enforced is changed
     *
     * @param caller - Address that created a pool
     * @param token - Address of the new token that will be enforced
     */
    event NewTokenEnforced(
        address indexed caller,
        address token
    );

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
     * @notice Create a new Pool with a custom name and symbol
     *
     * @param tokenSymbol - A short symbol for the token
     * @param tokenName - A descriptive name for the token
     *
     * @return pool - Address of new Pool contract
     */
    function newPool(string memory tokenSymbol, string memory tokenName)
        public
        returns (Pool pool)
    {
        // only the governance or the CRP pools can request to create core pools
        require(msg.sender == this.getController() || crpFactory.isCrp(msg.sender), "ERR_NOT_CONTROLLER");

        pool = new Pool(tokenSymbol, tokenName);
        _isPool[address(pool)] = true;
        emit LogNewPool(msg.sender, address(pool));
        pool.setController(msg.sender);
    }

    /**
     * @notice Create a new Pool with default name
     *
     * @dev This is what a CRPPool calls so it creates an internal unused token
     *
     * @return pool - Address of new Pool contract
     */
    function newPool() // solhint-disable-line ordering
        external
        returns (Pool pool)
    {
        return newPool("KIT", "Kassandra Internal Token");
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
        IcrpFactory(factoryAddr).isCrp(address(0));
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
        SmartPoolManager.verifyTokenCompliance(newAddr);
        emit NewTokenEnforced(msg.sender, newAddr);
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
        emit NewMinimum(msg.sender, percent);
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
