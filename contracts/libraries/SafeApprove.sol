// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../interfaces/IERC20.sol";

/**
 * @author PieDAO (ported to Balancer Labs) (ported to Kassandra)
 *
 * @title SafeApprove - set approval for tokens that require 0 prior approval
 *
 * @dev Perhaps to address the known ERC20 race condition issue
 *      See https://github.com/crytic/not-so-smart-contracts/tree/master/race_condition
 *      Some tokens - notably KNC - only allow approvals to be increased from 0
 */
library SafeApprove {
    /**
     * @notice Handle approvals of tokens that require approving from a base of 0
     *
     * @param token - The token we're approving
     * @param spender - Entity the owner (sender) is approving to spend his tokens
     * @param amount - Number of tokens being approved
     *
     * @return Boolean to confirm execution worked
     */
    function safeApprove(IERC20 token, address spender, uint amount) internal returns (bool) {
        uint currentAllowance = token.allowance(address(this), spender);

        // Do nothing if allowance is already set to this value
        if (currentAllowance == amount) {
            return true;
        }

        // If approval is not zero reset it to zero first
        if (currentAllowance != 0) {
            return token.approve(spender, 0);
        }

        // do the actual approval
        return token.approve(spender, amount);
    }
}
