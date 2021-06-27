/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');
const { assert } = require('chai');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

contract('configurableSwapFee', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let CRPPOOL;
    let WETH;
    let ABC;
    let weth;
    let dai;
    let abc;
    let xyz;

    // These are the intial settings for newCrp:
    const swapFee = 10 ** 15;
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';

    // const permissions = [false, true, false, false];
    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: true,
        canChangeWeights: false,
        canAddRemoveTokens: false,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    before(async () => {
        const coreFactory = await Factory.deployed();
        const crpFactory = await CRPFactory.deployed();
        xyz = await TToken.new('XYZ', 'XYZ', 18);
        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
        abc = await TToken.new('ABC', 'ABC', 18);

        WETH = weth.address;
        const DAI = dai.address;
        const XYZ = xyz.address;
        ABC = abc.address;

        // admin balances
        await weth.mint(admin, toWei('100'));
        await dai.mint(admin, toWei('15000'));
        await xyz.mint(admin, toWei('100000'));
        await abc.mint(admin, toWei('100000'));

        const tokenAddresses = [XYZ, WETH, DAI];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: tokenAddresses,
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        CRPPOOL = await crpFactory.newCrp.call(
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

        await crpPool.createPool(toWei('100'), 10, 10);
    });

    it('crpPool should have correct rights set', async () => {
        const swapRight = await crpPool.hasPermission(1);
        assert.isTrue(swapRight);

        let x;
        for (x = 0; x < permissions.length; x++) {
            if (x !== 1) {
                const otherPerm = await crpPool.hasPermission(x);
                assert.isFalse(otherPerm);
            }
        }
    });

    it('Non Controller account should not be able to change swapFee', async () => {
        await truffleAssert.reverts(
            crpPool.setSwapFee(toWei('0.001'), { from: accounts[1] }),
            'ERR_NOT_CONTROLLER',
        );
    });

    it('Controller should be able to change swapFee', async () => {
        const corePoolAddr = await crpPool.corePool();
        const corePool = await Pool.at(corePoolAddr);

        const deployedSwapFee = await corePool.getSwapFee();
        assert.equal(swapFee, deployedSwapFee);

        const newSwapFee = toWei('0.001');
        await crpPool.setSwapFee(newSwapFee);

        // Setting it to the same as the old value, so if it fails silently we wouldn't know
        // To guard against that, set it to something actually different in the next test, to
        // make sure it really changes it
        const newSwapFeeCheck = await corePool.getSwapFee();
        assert.equal(newSwapFee, newSwapFeeCheck);

        const differentSwapFee = toWei('0.003');
        await crpPool.setSwapFee(differentSwapFee);

        const secondSwapFeeCheck = await corePool.getSwapFee();
        assert.equal(differentSwapFee, secondSwapFeeCheck);
    });

    it('Configurable tokens should revert because non-permissioned', async () => {
        truffleAssert.reverts(
            crpPool.commitAddToken(ABC, toWei('1'), toWei('1')),
            'ERR_CANNOT_ADD_REMOVE_TOKENS',
        );

        truffleAssert.reverts(
            crpPool.applyAddToken(),
            'ERR_CANNOT_ADD_REMOVE_TOKENS',
        );

        truffleAssert.reverts(
            crpPool.removeToken(WETH),
            'ERR_CANNOT_ADD_REMOVE_TOKENS',
        );
    });

    it('Set public swap should revert because non-permissioned', async () => {
        await truffleAssert.reverts(
            crpPool.setPublicSwap(false),
            'ERR_NOT_PAUSABLE_SWAP',
        );
    });

    it('Should not be able to bypass crpPool', async () => {
        const corePoolAddr = await crpPool.corePool();
        const corePool = await Pool.at(corePoolAddr);

        const oldSwapFee = await corePool.getSwapFee();
        await truffleAssert.reverts(
            corePool.setSwapFee(toWei('0.007')),
            'ERR_NOT_CONTROLLER',
        );
        const newSwapFee = await corePool.getSwapFee();

        assert.equal(newSwapFee - oldSwapFee, 0);
    });

    it('Configurable weight should revert because non-permissioned', async () => {
        await truffleAssert.reverts(
            crpPool.updateWeight(xyz.address, toWei('13')),
            'ERR_NOT_CONFIGURABLE_WEIGHTS',
        );

        const block = await web3.eth.getBlock('latest');

        await truffleAssert.reverts(
            crpPool.updateWeightsGradually([toWei('2'), toWei('5'), toWei('5')], block.number, block.number + 10),
            'ERR_NOT_CONFIGURABLE_WEIGHTS',
        );

        await truffleAssert.reverts(
            crpPool.pokeWeights(),
            'ERR_NOT_CONFIGURABLE_WEIGHTS',
        );
    });
});
