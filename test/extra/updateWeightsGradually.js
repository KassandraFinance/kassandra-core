/* eslint-env es6 */
const { time } = require('@openzeppelin/test-helpers');
const { assert } = require('chai');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

const verbose = process.env.VERBOSE;

contract('updateWeightsGradually', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);
    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';
    const swapFee = 10 ** 15;

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    describe('Factory (update gradually)', () => {
        let controller;
        let WETH;
        let XYZ;
        let weth;
        let xyz;
        let startBlock;
        let endBlock;
        const startWeights = [toWei('1'), toWei('39')];
        const startBalances = [toWei('80000'), toWei('40')];
        let blockRange;

        before(async () => {
            const coreFactory = await Factory.deployed();
            const crpFactory = await CRPFactory.deployed();
            xyz = await TToken.new('XYZ', 'XYZ', 18);
            weth = await TToken.new('Wrapped Ether', 'WETH', 18);

            WETH = weth.address;
            XYZ = xyz.address;

            // admin balances
            await weth.mint(admin, toWei('100000000'));
            await xyz.mint(admin, toWei('100000000'));

            const poolParams = {
                poolTokenSymbol: SYMBOL,
                poolTokenName: NAME,
                constituentTokens: [XYZ, WETH],
                tokenBalances: startBalances,
                tokenWeights: startWeights,
                swapFee,
            };

            const CONTROLLER = await crpFactory.newCrp.call(
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
            await controller.setStrategy(admin);
        });

        describe('configurableWeights - update gradually', () => {
            it('Controller should be able to call updateWeightsGradually() with valid range', async () => {
                blockRange = 20;
                // get current block number
                const block = await web3.eth.getBlock('latest');

                if (verbose) {
                    console.log(`Block of updateWeightsGradually() call: ${block.number}`);
                }

                startBlock = block.number + 10;
                endBlock = startBlock + blockRange;
                const endWeights = [toWei('39'), toWei('1')];

                if (verbose) {
                    console.log(`Start block: ${startBlock}`);
                    console.log(`End   block: ${endBlock}`);
                }

                await controller.updateWeightsGradually(endWeights, startBlock, endBlock);
            });

            it('Should be able to pokeWeights(), stop in middle, and freeze', async () => {
                let weightXYZ;
                let weightWETH;

                let block = await web3.eth.getBlock('latest');

                if (verbose) {
                    console.log(`Block: ${block.number}`);
                }

                while (block.number < startBlock) {
                    // Wait for the start block
                    block = await web3.eth.getBlock('latest');

                    if (verbose) {
                        console.log(`Still waiting. Block: ${block.number}`);
                    }

                    await time.advanceBlock();
                }

                const corePoolAddr = await controller.corePool();
                const corePool = await Pool.at(corePoolAddr);

                // Only go half-way
                for (let i = 0; i < blockRange - 10; i++) {
                    if (verbose) {
                        weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                        weightWETH = await corePool.getDenormalizedWeight(WETH);
                        block = await web3.eth.getBlock('latest');
                        console.log(
                            `Block: ${block.number}. `
                            + `Weights -> XYZ: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                            + `\tWETH: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                        );
                    }

                    await controller.pokeWeights();
                }

                // Call update with current weights to "freeze"
                if (verbose) {
                    console.log('Freeze at current weight');
                }

                weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                weightWETH = await corePool.getDenormalizedWeight(WETH);
                const endWeights = [weightXYZ, weightWETH];

                await controller.updateWeightsGradually(endWeights, startBlock, endBlock + 10);

                for (let i = 0; i < blockRange + 10; i++) {
                    weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                    weightWETH = await corePool.getDenormalizedWeight(WETH);

                    assert.isTrue(weightXYZ - endWeights[0] === 0);
                    assert.isTrue(weightWETH - endWeights[1] === 0);

                    if (verbose) {
                        block = await web3.eth.getBlock('latest');
                        console.log(
                            `Block: ${block.number}. `
                            + `Weights -> XYZ: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                            + `\tWETH: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                        );
                    }

                    await controller.pokeWeights();
                }
            });

            it('Controller should be able to call updateWeightsGradually() again', async () => {
                blockRange = 50;
                // get current block number
                let block = await web3.eth.getBlock('latest');
                startBlock = block.number + 10;
                endBlock = startBlock + blockRange;
                const endWeights = [toWei('1'), toWei('39')];

                if (verbose) {
                    console.log(`Start block: ${startBlock}`);
                    console.log(`End   block: ${endBlock}`);

                    console.log('Go back down');
                }

                await controller.updateWeightsGradually(endWeights, startBlock, endBlock);

                if (verbose) {
                    console.log(`Block: ${block.number}`);
                }

                while (block.number < startBlock) {
                    // Wait for the start block
                    block = await web3.eth.getBlock('latest');

                    if (verbose) {
                        console.log(`Still waiting. Block: ${block.number}`);
                    }

                    await time.advanceBlock();
                }

                let weightXYZ;
                let weightWETH;
                const corePoolAddr = await controller.corePool();
                const corePool = await Pool.at(corePoolAddr);

                for (let i = 0; i < blockRange + 5; i++) {
                    if (verbose) {
                        weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                        weightWETH = await corePool.getDenormalizedWeight(WETH);
                        block = await web3.eth.getBlock('latest');
                        console.log(
                            `Block: ${block.number}. `
                            + `Weights -> XYZ: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                            + `\tWETH: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                        );
                    }

                    await controller.pokeWeights();
                }

                weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                weightWETH = await corePool.getDenormalizedWeight(WETH);

                // Verify the end weights match
                assert.isTrue(weightXYZ - endWeights[0] === 0);
                assert.isTrue(weightWETH - endWeights[1] === 0);
            });

            describe('crack mode', () => {
                it('Should allow calling repeatedly', async () => {
                    startBlock = await web3.eth.getBlock('latest');
                    endBlock = startBlock.number + 20;

                    for (let i = 0; i < 20; i++) {
                        const currXYZWeight = Math.floor((Math.random() * 20) + 1).toString();
                        const currWETHWeight = Math.floor((Math.random() * 20) + 1).toString();

                        startBlock = await web3.eth.getBlock('latest');
                        endBlock = startBlock.number + 20;

                        if (verbose) {
                            console.log(`XYZ target weight: ${currXYZWeight}`);
                            console.log(`WETH target weight: ${currWETHWeight}`);
                        }

                        const endWeights = [toWei(currXYZWeight), toWei(currWETHWeight)];

                        await controller.updateWeightsGradually(endWeights, startBlock.number, endBlock);

                        for (let j = 0; j < 5; j++) {
                            if (verbose) {
                                const corePoolAddr = await controller.corePool();
                                const corePool = await Pool.at(corePoolAddr);
                                const weightXYZ = await corePool.getDenormalizedWeight(XYZ);
                                const weightWETH = await corePool.getDenormalizedWeight(WETH);
                                const block = await web3.eth.getBlock('latest');
                                console.log(
                                    `Block: ${block.number}. `
                                    + `Weights -> XYZ: ${((weightXYZ * 2.5) / 10 ** 18).toFixed(4)}%`
                                    + `\tWETH: ${((weightWETH * 2.5) / 10 ** 18).toFixed(4)}%`,
                                );
                            }

                            await controller.pokeWeights();
                        }
                    }
                }).timeout(0);
            });
        });
    });
});
