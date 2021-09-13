/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const { calcOutGivenIn, calcRelativeDiff } = require('../../lib/calc_comparisons');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

const verbose = process.env.VERBOSE;

contract('configurableWeights_withSwaps', async (accounts) => {
    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];

    const { toWei, fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);
    const errorDelta = 10 ** -4;
    const swapFee = 10 ** 15;

    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    describe('CWS Factory', () => {
        let controller;
        let CONTROLLER;
        let WETH;
        let XYZ;
        let weth;
        let xyz;
        let abc;
        const startWeights = [toWei('1'), toWei('39')];
        const startBalances = [toWei('80000'), toWei('40')];
        let blockRange;

        before(async () => {
            const coreFactory = await Factory.deployed();
            const crpFactory = await CRPFactory.deployed();
            xyz = await TToken.new('XYZ', 'XYZ', 18);
            weth = await TToken.new('Wrapped Ether', 'WETH', 18);
            abc = await TToken.new('ABC', 'ABC', 18);

            WETH = weth.address;
            XYZ = xyz.address;

            // admin balances
            await weth.mint(admin, toWei('100000000'));
            await xyz.mint(admin, toWei('100000000'));
            await abc.mint(admin, toWei('100000000'));

            // user balances
            await weth.mint(user1, toWei('100000000'));
            await xyz.mint(user1, toWei('100000000'));
            await abc.mint(user1, toWei('100000000'));

            await weth.mint(user2, toWei('100000000'));
            await xyz.mint(user2, toWei('100000000'));
            await abc.mint(user2, toWei('100000000'));

            const poolParams = {
                poolTokenSymbol: SYMBOL,
                poolTokenName: NAME,
                constituentTokens: [XYZ, WETH],
                tokenBalances: startBalances,
                tokenWeights: startWeights,
                swapFee,
            };

            CONTROLLER = await crpFactory.newCrp.call(
                coreFactory.address,
                poolParams,
                permissions,
            );

            await crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            );

            controller = await ConfigurableRightsPool.at(CONTROLLER);

            const CONTROLLER_ADDRESS = controller.address;

            await weth.approve(CONTROLLER_ADDRESS, MAX);
            await xyz.approve(CONTROLLER_ADDRESS, MAX);

            await controller.createPool(toWei('100'), 10, 10);
            await controller.setStrategist(admin, { from: admin });
        });

        it('Controller should be able to call updateWeightsGradually() with valid range', async () => {
            blockRange = 20;
            // get current block number
            const block = await web3.eth.getBlock('latest');
            const startBlock = block.number + 3;
            const endBlock = startBlock + blockRange;
            const endWeights = [toWei('39'), toWei('1')];

            if (verbose) {
                console.log(`Start block for June -> July flipping: ${startBlock}`);
                console.log(`End   block for June -> July flipping: ${endBlock}`);
            }

            await controller.updateWeightsGradually(endWeights, startBlock, endBlock);
        });

        it('Should revert because too early to pokeWeights()', async () => {
            if (verbose) {
                const block = await web3.eth.getBlock('latest');
                console.log(`Block: ${block.number}`);
            }

            await truffleAssert.reverts(
                controller.pokeWeights(),
                'ERR_CANT_POKE_YET',
            );
        });

        it('Should be able to pokeWeights()', async () => {
            const corePoolAddr = await controller.corePool();
            const underlyingPool = await Pool.at(corePoolAddr);

            // Pool was created by CRP
            const owner = await underlyingPool.getController();
            assert.equal(owner, CONTROLLER);

            // By definition, underlying pool is not finalized
            const finalized = await underlyingPool.isFinalized();
            assert.isFalse(finalized);

            await truffleAssert.reverts(
                underlyingPool.finalize(), 'ERR_NOT_CONTROLLER',
            );

            const numTokens = await underlyingPool.getNumTokens();
            assert.equal(numTokens, 2);

            const poolTokens = await underlyingPool.getCurrentTokens();
            assert.equal(poolTokens[0], XYZ);
            assert.equal(poolTokens[1], WETH);

            // Enable swaps
            await xyz.approve(underlyingPool.address, MAX, { from: user1 });
            await weth.approve(underlyingPool.address, MAX, { from: user1 });
            let tokenIn;
            let tokenOut;
            let tokenInBalance;
            let tokenInWeight;
            let tokenOutBalance;
            let tokenOutWeight;
            let expectedTotalOut;
            let tokenAmountOut;
            let relDif;
            let swapAmount;

            const poolSwapFee = await underlyingPool.getSwapFee();

            for (let i = 0; i < blockRange + 10; i++) {
                if (verbose) {
                    const weightXYZ = await controller.getDenormalizedWeight(XYZ);
                    const weightWETH = await controller.getDenormalizedWeight(WETH);
                    const block = await web3.eth.getBlock('latest');
                    console.log(
                        `Block: ${block.number}. `
                        + `Weights -> July: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                        + `\tJune: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                    );
                }

                await controller.pokeWeights();

                if (i % 3 === 0) {
                    // Randomly transfer tokens to the pool
                    const xferAmount = Math.floor((Math.random() * 3) + 1).toString();

                    if (Math.random() > 0.5) {
                        if (verbose) {
                            console.log(`Randomly transferring ${xferAmount} WETH into pool`);
                        }

                        await weth.transfer(underlyingPool.address, toWei(xferAmount), { from: user1 });
                    } else {
                        if (verbose) {
                            console.log(`Randomly transferring ${xferAmount} XYZ into pool`);
                        }

                        await xyz.transfer(underlyingPool.address, toWei(xferAmount), { from: user2 });
                    }

                    // Transferring tokens randomly into the pool causes
                    //   _records[token].balance (used by the core Pool methods like swapExactAmountIn)
                    //   to get out of sync with the ERC20.balanceOf figure
                    //
                    await underlyingPool.gulp(XYZ);
                    await underlyingPool.gulp(WETH);
                }

                // Swap back and forth
                if (i % 2 === 0) {
                    swapAmount = Math.floor((Math.random() * 10) + 1).toString();

                    if (verbose) {
                        console.log(`Swapping ${swapAmount} XYZ for WETH`);
                    }

                    tokenIn = XYZ;
                    tokenOut = WETH;

                    tokenInBalance = await xyz.balanceOf.call(underlyingPool.address);
                    tokenInWeight = await underlyingPool.getDenormalizedWeight(XYZ);
                    tokenOutBalance = await weth.balanceOf.call(underlyingPool.address);
                    tokenOutWeight = await underlyingPool.getDenormalizedWeight(WETH);

                    expectedTotalOut = calcOutGivenIn(
                        fromWei(tokenInBalance),
                        fromWei(tokenInWeight),
                        fromWei(tokenOutBalance),
                        fromWei(tokenOutWeight),
                        swapAmount,
                        fromWei(poolSwapFee),
                    );

                    tokenAmountOut = await underlyingPool.swapExactAmountIn.call(
                        tokenIn,
                        toWei(swapAmount), // tokenAmountIn
                        tokenOut,
                        toWei('0'), // minAmountOut
                        MAX,
                        { from: user1 },
                    );

                    relDif = calcRelativeDiff(expectedTotalOut, fromWei(tokenAmountOut[0]));
                    assert.isAtMost(relDif.toNumber(), errorDelta);
                } else {
                    swapAmount = Math.floor((Math.random() * 10) + 1).toString();

                    if (verbose) {
                        console.log(`Swapping ${swapAmount} WETH for XYZ`);
                    }

                    tokenIn = WETH;
                    tokenOut = XYZ;

                    tokenInBalance = await weth.balanceOf.call(underlyingPool.address);
                    tokenInWeight = await underlyingPool.getDenormalizedWeight(WETH);
                    tokenOutBalance = await xyz.balanceOf.call(underlyingPool.address);
                    tokenOutWeight = await underlyingPool.getDenormalizedWeight(XYZ);

                    expectedTotalOut = calcOutGivenIn(
                        fromWei(tokenInBalance),
                        fromWei(tokenInWeight),
                        fromWei(tokenOutBalance),
                        fromWei(tokenOutWeight),
                        swapAmount,
                        fromWei(poolSwapFee),
                    );

                    tokenAmountOut = await underlyingPool.swapExactAmountIn.call(
                        tokenIn,
                        toWei(swapAmount), // tokenAmountIn
                        tokenOut,
                        toWei('0'), // minAmountOut
                        MAX,
                        { from: user1 },
                    );

                    relDif = calcRelativeDiff(expectedTotalOut, fromWei(tokenAmountOut[0]));
                    assert.isAtMost(relDif.toNumber(), errorDelta);
                }
            }
        });
    });
});
