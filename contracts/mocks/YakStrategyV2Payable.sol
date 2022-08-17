// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Token.sol";

abstract contract YakStrategyV2Payable is TokenBase {
    function deposit() external payable virtual;
}
