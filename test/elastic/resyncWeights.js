/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ElasticSupplyPool = artifacts.require('ElasticSupplyPool');
const ESPFactory = artifacts.require('ESPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

contract('elasticSupplyPool', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;
    const startWeights = [toWei('20'), toWei('20')];
    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let usdc;
    let dai;
    let USDC;
    let DAI;

    // These are the intial settings for newCrp:
    const swapFee = 10 ** 15;
    const SYMBOL = 'BAL-USDC-DAI';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: true,
        canAddRemoveTokens: false,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    describe('resyncWeight', () => {
        before(async () => {
            const coreFactory = await Factory.deployed();
            const crpFactory = await ESPFactory.deployed();

            usdc = await TToken.new('USD Stablecoin', 'USDC', 18);
            dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

            USDC = usdc.address;
            DAI = dai.address;

            // admin balances
            await dai.mint(admin, toWei('15000'));
            await usdc.mint(admin, toWei('15000'));

            const tokenAddresses = [USDC, DAI];
            const startBalances = [toWei('10000'), toWei('10000')];

            const poolParams = {
                poolTokenSymbol: SYMBOL,
                poolTokenName: NAME,
                constituentTokens: tokenAddresses,
                tokenBalances: startBalances,
                tokenWeights: startWeights,
                swapFee,
            };

            const CRPPOOL = await crpFactory.newEsp.call(
                coreFactory.address,
                poolParams,
                permissions,
            );

            await crpFactory.newEsp(
                coreFactory.address,
                poolParams,
                permissions,
            );

            crpPool = await ElasticSupplyPool.at(CRPPOOL);
            const CRPPOOL_ADDRESS = crpPool.address;
            await usdc.approve(CRPPOOL_ADDRESS, MAX);
            await dai.approve(CRPPOOL_ADDRESS, MAX);

            await crpPool.createPool(toWei('100'));
        });

        it('resync weights should gulp and not move price', async () => {
            const corePoolAddr = await crpPool.corePool();
            const corePool = await Pool.at(corePoolAddr);

            // both pools are out of balance
            // calling gulp after transfer will move the price
            await dai.transfer(corePoolAddr, toWei('1000'));

            // resync weights, safely calls gulp and adjusts weights
            // proportionally so that price does not move
            const spotPriceBefore = await corePool.getSpotPrice.call(dai.address, usdc.address);

            await crpPool.resyncWeight(dai.address);

            const spotPriceAfter = await corePool.getSpotPrice.call(dai.address, usdc.address);

            assert.equal(spotPriceBefore.toString(), spotPriceAfter.toString());
        });

        it('Should not allow calling updateWeight', async () => {
            await truffleAssert.reverts(
                crpPool.updateWeight(DAI, toWei('3')),
                'ERR_UNSUPPORTED_OPERATION',
            );
        });

        it('Should not allow calling updateWeightsGradually', async () => {
            await truffleAssert.reverts(
                crpPool.updateWeightsGradually(startWeights, 10, 10),
                'ERR_UNSUPPORTED_OPERATION',
            );
        });

        it('Should not allow calling pokeWeights', async () => {
            await truffleAssert.reverts(
                crpPool.pokeWeights(), 'ERR_UNSUPPORTED_OPERATION',
            );
        });

        it('Should not allow calling overloaded createPool', async () => {
            await truffleAssert.reverts(
                crpPool.createPool(toWei('100'), 10, 10), 'ERR_UNSUPPORTED_OPERATION',
            );
        });
    });
});
