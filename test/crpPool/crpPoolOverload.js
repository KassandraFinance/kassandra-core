/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

/*
Tests initial CRP Pool set-up including:
Pool deployment, token binding, balance checks, tokens checks.
*/
contract('crpPoolOverloadTests', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;
    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
    const MAX = web3.utils.toTwosComplement(-1);
    // These are the intial settings for newCrp:
    const swapFee = toWei('0.003');
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: true,
        canChangeSwapFee: true,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    let crpPool;

    before(async () => {
        const coreFactory = await Factory.deployed();
        const crpFactory = await CRPFactory.deployed();
        const xyz = await TToken.new('XYZ', 'XYZ', 18);
        const weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        const dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

        const WETH = weth.address;
        const DAI = dai.address;
        const XYZ = xyz.address;

        // admin balances
        await weth.mint(admin, toWei('100'));
        await dai.mint(admin, toWei('15000'));
        await xyz.mint(admin, toWei('100000'));

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        const CRPPOOL = await crpFactory.newCrp.call(
            coreFactory.address,
            poolParams,
            permissions,
        );

        await crpFactory.newCrp(
            coreFactory.address,
            poolParams,
            permissions,
        );

        crpPool = await ConfigurableRightsPool.at(CRPPOOL);

        const CRPPOOL_ADDRESS = crpPool.address;

        await weth.approve(CRPPOOL_ADDRESS, MAX);
        await dai.approve(CRPPOOL_ADDRESS, MAX);
        await xyz.approve(CRPPOOL_ADDRESS, MAX);
    });

    // Removed minimums
    it.skip('crpPool should not create pool with invalid minimumWeightChangeBlockPeriod', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100'), 5, 10),
            'ERR_INVALID_BLOCK_PERIOD',
        );
    });

    it.skip('crpPool should not create pool with invalid addTokenTimeLockInBlocks', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100'), 10, 5),
            'ERR_INVALID_TOKEN_TIME_LOCK',
        );
    });

    it('crpPool should not create pool with inconsistent time parameters', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100'), 10, 20), 'ERR_INCONSISTENT_TOKEN_TIME_LOCK',
        );
    });

    it('crpPool should not create pool with negative time parameters', async () => {
        await truffleAssert.reverts(
            // 0 > -10, but still shouldn't work
            crpPool.createPool(toWei('100'), 0, web3.utils.toTwosComplement(-10)), 'ERR_INCONSISTENT_TOKEN_TIME_LOCK',
        );
    });

    it('crpPool should have a core Pool after creation', async () => {
        await crpPool.createPool(toWei('100'), 0, 0);
        const corePoolAddr = await crpPool.corePool();
        assert.notEqual(corePoolAddr, ZERO_ADDRESS);
        await Pool.at(corePoolAddr);
    });
});
