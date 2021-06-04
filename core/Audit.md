- [Installation](#Installation)
- [Testing with Echidna](#testing-properties-with-echidna)
- [Code verification with Manticore](#Code-verification-with-Manticore)

# Installation

**Slither**
```
pip3 install slither-analyzer
```

**Manticore**
```
pip3 install manticore
```

**Echidna**
See [Echidna Installation](https://github.com/crytic/building-secure-contracts/tree/master/program-analysis/echidna#installation).


```
docker run -it -v "$PWD":/home/training trailofbits/eth-security-toolbox
```

```
solc-select 0.5.12
cd /home/training
```


# Testing properties with Echidna

`slither-flat` will export the contract and translate external function to public, to faciliate writting properties:
```
slither-flat . --convert-external
```

The flattened contracts are in `crytic-export/flattening`. The Echidna properties are in `echidna/`.

## Properties

Echidna properties can be broadly divided in two categories: general properties of the contracts that states what user can and cannot do and
specific properties based on unit tests.

To test a property, run `echidna-test echidna/CONTRACT_file.sol CONTRACT_name --config echidna/CONTRACT_name.yaml`.

## General Properties

| Description    | Name           | Contract      | Finding   | Status   |
| :---                                                            |     :---:              |         :---:   |  :---:   | :---:   |
| An attacker cannot steal assets from a public pool.              | [`attacker_token_balance`](echidna/TPoolBalance.sol#L22-L25)   | [`TPoolBalance`](echidna/TPoolBalance.sol) |FAILED ([#193](https://github.com/balancer-labs/balancer-core/issues/193))| **Fixed** |
| An attacker cannot force the pool balance to be out-of-sync.  | [`pool_record_balance`](echidna/TPoolBalance.sol#L27-L33)  | [`TPoolBalance`](echidna/TPoolBalance.sol)|PASSED|  |
| An attacker cannot generate free pool tokens with `joinPool` (1, 2).  | [`joinPool`](contracts/test/echidna/TPoolJoinPool.sol#L7-L31)  | [`TPoolJoinPool`](contracts/test/echidna/TPoolBalance.sol)|FAILED ([#204](https://github.com/balancer-labs/balancer-core/issues/204))|  **Mitigated** |
| Calling `joinPool-exitPool` does not lead to free pool tokens (no fee) (1, 2).  | [`joinPool`](contracts/test/echidna/TPoolJoinExitPoolNoFee.sol#L34-L59)  | [`TPoolJoinExitNoFee`](contracts/test/echidna/TPoolJoinExitPoolNoFee.sol)|FAILED ([#205](https://github.com/balancer-labs/balancer-core/issues/205))| **Mitigated** |
| Calling `joinPool-exitPool` does not lead to free pool tokens (with fee) (1, 2).  | [`joinPool`](contracts/test/echidna/TPoolJoinExitPool.sol#L37-L62)  | [`TPoolJoinExit`](contracts/test/echidna/TPoolJoinExitPool.sol)|FAILED ([#205](https://github.com/balancer-labs/balancer-core/issues/205))| **Mitigated** |
| Calling `exitswapExternAmountOut` does not lead to free asset (1).  | [`exitswapExternAmountOut`](echidna/TPoolExitSwap.sol#L8-L21)  | [`TPoolExitSwap`](contracts/test/echidna/TPoolExitSwap.sol)|FAILED ([#203](https://github.com/balancer-labs/balancer-core/issues/203))| **Mitigated** |


(1) These properties target a specific piece of code.

(2) These properties don't need slither-flat, and are integrated into `contracts/test/echidna/`. To test them run `echidna-test . CONTRACT_name --config ./echidna_general_config.yaml`.

## Unit-test-based Properties

| Description    | Name           | Contract      | Finding   |  Status   |
| :---                                                            |     :---:              |         :---:   |  :---:   |  :---:   |
| If the controller calls `setController`, then the `getController()` should return the new controller.  | [`controller_should_change`](echidna/TPoolController.sol#L6-L13)  | [`TPoolController`](echidna/TPoolController.sol)|PASSED| |
| The controller cannot be changed to a null address (`0x0`).  | [`controller_cannot_be_null`](echidna/TPoolController.sol#L15-L23)  | [`TPoolController`](echidna/TPoolController.sol)|FAILED ([#198](https://github.com/balancer-labs/balancer-core/issues/198))| **WONT FIX** |
| The controller cannot be changed by other users.  | [`no_other_user_can_change_the_controller`](echidna/TPoolController.sol#L28-L31)  | [`TPoolController`](echidna/TPoolController.sol)|PASSED| |
| The sum of normalized weight should be 1 if there are tokens binded.  | [`valid_weights`](echidna/TPoolLimits.sol#L35-L52)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |FAILED ([#208](https://github.com/balancer-labs/balancer-core/issues/208)| **Mitigated** |
| The balances of all the tokens are greater or equal than `MIN_BALANCE`.  | [`min_token_balance`](echidna/TPoolLimits.sol#L65-L74)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |FAILED ([#210](https://github.com/balancer-labs/balancer-core/issues/210)) | **WONT FIX**|
| The weight of all the tokens are less or equal than `MAX_WEIGHT`.  | [`max_weight`](echidna/TPoolLimits.sol#L76-L85)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |PASSED| |
| The weight of all the tokens are greater or equal than `MIN_WEIGHT`.  | [`min_weight`](echidna/TPoolLimits.sol#L87-L96)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |PASSED| |
| The swap fee is less or equal tan `MAX_FEE`. | [`min_swap_free`](echidna/TPoolLimits.sol#L99-L102)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |PASSED| |
| The swap fee is greater or equal than `MIN_FEE`.  | [`max_swap_free`](echidna/TPoolLimits.sol#L104-L107)  | [`TPoolLimits`](echidna/TPoolLimits.sol) |PASSED| |
| An user can only swap in less than 50% of the current balance of tokenIn for a given pool. | [`max_swapExactAmountIn`](echidna/TPoolLimits.sol#L134-L156) | [`TPoolLimits`](echidna/TPoolLimits.sol) |FAILED ([#212](https://github.com/balancer-labs/balancer-core/issues/212))| **Fixed** |
| An user can only swap out less than 33.33% of the current balance of tokenOut for a given pool. | [`max_swapExactAmountOut`](echidna/TPoolLimits.sol#L109-L132) | [`TPoolLimits`](echidna/TPoolLimits.sol) |FAILED ([#212](https://github.com/balancer-labs/balancer-core/issues/212))|  **Fixed** |
| If a token is bounded, the `getSpotPrice` should never revert.  | [`getSpotPrice_no_revert`](echidna/TPoolNoRevert.sol#L34-L44)  | [`TPoolNoRevert`](echidna/TPoolNoRevert.sol) |PASSED| |
| If a token is bounded, the `getSpotPriceSansFee` should never revert.  | [`getSpotPriceSansFee_no_revert`](echidna/TPoolNoRevert.sol#L46-L56)  | [`TPoolNoRevert`](echidna/TPoolNoRevert.sol) |PASSED| |
| Calling `swapExactAmountIn` with a small value of the same token should never revert.  | [`swapExactAmountIn_no_revert`](echidna/TPoolNoRevert.sol#L58-L77)  | [`TPoolNoRevert`](echidna/TPoolNoRevert.sol) |PASSED| |
| Calling `swapExactAmountOut` with a small value of the same token should never revert. | [`swapExactAmountOut_no_revert`](echidna/TPoolNoRevert.sol#L79-L99)  | [`TPoolNoRevert`](echidna/TPoolNoRevert.sol) |PASSED| |
| If a user joins pool and exits it with the same amount, the balances should keep constant.  | [`joinPool_exitPool_balance_consistency`](echidna/TPoolJoinExit.sol#L48-L97)  | [`TPoolJoinExit`](echidna/TPoolJoinExit.sol) |PASSED| |
| If a user joins pool and exits it with a larger amount, `exitPool` should revert.  | [`impossible_joinPool_exitPool`](echidna/TPoolJoinExit.sol#L99-L112) | [`TPoolJoinExit`](echidna/TPoolJoinExit.sol) |PASSED| |
| It is not possible to bind more than `MAX_BOUND_TOKENS`. | [`getNumTokens_less_or_equal_MAX_BOUND_TOKENS`](echidna/TPoolBind.sol#L40-L43)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| It is not possible to bind more than once the same token.  | [`bind_twice`](echidna/TPoolBind.sol#L45-L54)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| It is not possible to unbind more than once the same token. | [`unbind_twice`](echidna/TPoolBind.sol#L56-L66)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| It is always possible to unbind a token.  | [`all_tokens_are_unbindable`](echidna/TPoolBind.sol#L68-L81)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| All tokens are rebindable with valid parameters. | [`all_tokens_are_rebindable_with_valid_parameters`](echidna/TPoolBind.sol#L83-L95)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| It is not possible to rebind an unbinded token. | [`rebind_unbinded`](echidna/TPoolBind.sol#L97-L107)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| Only the controller can bind. | [`when_bind`](echidna/TPoolBind.sol#L150-L154) and [`only_controller_can_bind`](echidna/TPoolBind.sol#L145-L148) | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| If a user that is not the controller, tries to bind, rebind or unbind, the operation will revert. | [`when_bind`](echidna/TPoolBind.sol#L150-L154), [`when_rebind`](echidna/TPoolBind.sol#L150-L154) and [`when_unbind`](echidna/TPoolBind.sol#L163-L168)  | [`TPoolBind`](echidna/TPoolBind.sol) |PASSED| |
| Transfer tokens to the null address (`0x0`) causes a revert | [`transfer_to_zero`](echidna/TTokenERC20.sol#L75-L79) and [`transferFrom_to_zero`](echidna/TTokenERC20.sol#L85-L89) | [`TTokenERC20`](echidna/TTokenERC20.sol) |FAILED ([#197](https://github.com/balancer-labs/balancer-core/issues/197))| **WONT FIX** |
| The null address (`0x0`) owns no tokens | [`zero_always_empty`](echidna/TTokenERC20.sol#L34-L36) | [`TTokenERC20`](echidna/TTokenERC20.sol) |FAILED| **WONT FIX** |
| Transfer a valid amout of tokens to non-null address reduces the current balance | [`transferFrom_to_other`](echidna/TTokenERC20.sol#L108-L113) and [`transfer_to_other`](echidna/TTokenERC20.sol#L131-L142)  | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |
| Transfer an invalid amout of tokens to non-null address reverts or returns false | [`transfer_to_user`](echidna/TTokenERC20.sol#L149-L155) | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |
| Self transfer a valid amout of tokens keeps the current balance constant | [`self_transferFrom`](echidna/TTokenERC20.sol#L96-L101) and [`self_transfer`](echidna/TTokenERC20.sol#L120-L124) | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |
| Approving overwrites the previous allowance value | [`approve_overwrites`](echidna/TTokenERC20.sol#L42-L49) | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |
| The `totalSupply` is a constant | [`totalSupply_constant`](echidna/TTokenERC20.sol#L166-L168) | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |
| The balances are consistent with the `totalSupply` | [`totalSupply_balances_consistency`](echidna/TTokenERC20.sol#L63-L65) and [`balance_less_than_totalSupply`](echidna/TTokenERC20.sol#L55-L57) | [`TTokenERC20`](echidna/TTokenERC20.sol) |PASSED| |

# Code verification with Manticore

The following properties have equivalent Echidna property, but Manticore allows to either prove the absence of bugs, or look for an upper bound.

To execute the script, run `python3 ./manticore/script_name.py`.

| Description    | Script           | Contract      | Status   |
| :---                                                            |     :---:              |         :---:   |  :---:   |
| An attacker cannot generate free pool tokens with `joinPool`.  |   [`TPoolJoinPool.py`](manticore/TPoolJoinPool.py)| [`TPoolJoinPool`](manticore/contracts/TPoolJoinPool.sol) | **FAILED** ([#204](https://github.com/balancer-labs/balancer-core/issues/204)) |
| Calling `joinPool-exitPool` does not lead to free pool tokens (no fee). | [`TPoolJoinExitNoFee.py`](manticore/TPoolJoinExitNoFee.py) | [`TPoolJoinExitPoolNoFee`](manticore/contracts/TPoolJoinExitPoolNoFee.sol)  |**FAILED** ([#205](https://github.com/balancer-labs/balancer-core/issues/205)) |
| Calling `joinPool-exitPool` does not lead to free pool tokens (with fee).| [`TPoolJoinExit.py`](manticore/TPoolJoinExit.py)   | [`TPoolJoinExit`](manticore/contracts/TPoolJoinExitPool.sol) |**FAILED** ([#205](https://github.com/balancer-labs/balancer-core/issues/205))|
