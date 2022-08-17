// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Token.sol";

abstract contract YakStrategyV2 is TokenBase {
    function deposit(uint amount) external virtual;
    function getSharesForDepositTokens(uint amount) external virtual view returns (uint);
}
