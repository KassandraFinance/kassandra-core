/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

const verbose = process.env.VERBOSE;

contract('configurableWeights_withTx', async (accounts) => {
    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];

    const swapFee = 10 ** 15;

    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);
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

    describe('Factory', () => {
        let controller;
        let CONTROLLER;
        let WETH;
        let XYZ;
        let weth;
        let dai;
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
            dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
            abc = await TToken.new('ABC', 'ABC', 18);

            WETH = weth.address;
            XYZ = xyz.address;

            // admin balances
            await weth.mint(admin, toWei('100000000'));
            await dai.mint(admin, toWei('100000000'));
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
            await dai.approve(CONTROLLER_ADDRESS, MAX);
            await xyz.approve(CONTROLLER_ADDRESS, MAX);

            await controller.createPool(toWei('100'), 10, 10);
            await controller.setStrategy(admin, { from: admin });
        });

        describe('configurableWeights / Tx', () => {
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
                const poolAmountOut1 = '1';
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

                let xyzBalance;
                let wethBalance;
                let xyzSpotPrice;
                let lastXyzPrice;
                let wethSpotPrice;
                let lastWethPrice;

                for (let i = 0; i < blockRange + 10; i++) {
                    if (verbose) {
                        const weightXYZ = await underlyingPool.getDenormalizedWeight(XYZ);
                        const weightWETH = await underlyingPool.getDenormalizedWeight(WETH);
                        const block = await web3.eth.getBlock('latest');
                        console.log(
                            `Block: ${block.number}. `
                            + `Weights -> July: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                            + `\tJune: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                        );
                    }

                    await controller.pokeWeights();

                    // Balances should not change
                    xyzBalance = await underlyingPool.getBalance(XYZ);
                    wethBalance = await underlyingPool.getBalance(WETH);

                    assert.equal(xyzBalance, startBalances[0]);
                    assert.equal(wethBalance, startBalances[1]);

                    if (lastXyzPrice) {
                        xyzSpotPrice = await underlyingPool.getSpotPrice(XYZ, WETH);
                        wethSpotPrice = await underlyingPool.getSpotPrice(WETH, XYZ);

                        // xyz price should be going up; weth price should be going down
                        assert.isTrue(xyzSpotPrice <= lastXyzPrice);
                        assert.isTrue(wethSpotPrice >= lastWethPrice);

                        lastXyzPrice = xyzSpotPrice;
                        lastWethPrice = wethSpotPrice;
                    }

                    if (i === 5) {
                        // Random user tries to join underlying pool (cannot - not finalized)
                        await truffleAssert.reverts(
                            underlyingPool.joinPool(toWei(poolAmountOut1), [MAX, MAX, MAX], { from: user1 }),
                            'ERR_NOT_FINALIZED',
                        );
                    }
                }
            });
        });
    });
});
