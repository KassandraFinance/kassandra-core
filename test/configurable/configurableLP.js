/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

contract('configurableLPNoWhitelist', async (accounts) => {
    const admin = accounts[0];
    const admin2 = accounts[1];
    const admin3 = accounts[2];

    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let weth; let dai; let xyz;

    // These are the intial settings for newCrp:
    const swapFee = 10 ** 15;
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';

    // All off
    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
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

        const WETH = weth.address;
        const DAI = dai.address;
        const XYZ = xyz.address;

        // admin balances
        await weth.mint(admin, toWei('100'));
        await dai.mint(admin, toWei('15000'));
        await xyz.mint(admin, toWei('100000'));

        const tokenAddresses = [XYZ, WETH, DAI];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: tokenAddresses,
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

        await crpPool.createPool(toWei('100'), 10, 10);
    });

    describe('Anyone can provide liquidity when there is no whitelist', () => {
        it('owner and two other accounts', async () => {
            let hasPerm = await crpPool.canProvideLiquidity(admin);
            assert.isTrue(hasPerm, 'Admin cannot provide liquidity');

            hasPerm = await crpPool.canProvideLiquidity(admin2);
            assert.isTrue(hasPerm, 'Admin cannot provide liquidity');

            hasPerm = await crpPool.canProvideLiquidity(admin3);
            assert.isTrue(hasPerm, 'Admin cannot provide liquidity');
        });

        it.skip('Except the null address', async () => {
            const hasPerm = await crpPool.canProvideLiquidity(ZERO_ADDRESS);
            assert.isFalse(hasPerm, 'Null address can provide liquidity');
        });
    });

    it('Cannot whitelist without permission', async () => {
        await truffleAssert.reverts(
            crpPool.whitelistLiquidityProvider(admin),
            'ERR_CANNOT_WHITELIST_LPS',
        );
    });

    it('crpPool should have correct rights set', async () => {
        const response = [];
        const original = Object.values(permissions);

        for (let x = 0; x < original.length; x++) {
            const perm = await crpPool.hasPermission(x);
            response.push(perm);
        }

        assert.sameOrderedMembers(response, original);
    });
});

contract('configurableLP', async (accounts) => {
    const admin = accounts[0];
    const admin2 = accounts[1];
    const admin3 = accounts[2];

    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let weth; let dai; let xyz;

    // These are the intial settings for newCrp:
    const swapFee = 10 ** 15;
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = 'KSP';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: false,
        canAddRemoveTokens: false,
        canWhitelistLPs: true,
    };

    before(async () => {
        const coreFactory = await Factory.deployed();
        const crpFactory = await CRPFactory.deployed();
        xyz = await TToken.new('XYZ', 'XYZ', 18);
        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

        const WETH = weth.address;
        const DAI = dai.address;
        const XYZ = xyz.address;

        // admin balances
        await weth.mint(admin, toWei('100'));
        await dai.mint(admin, toWei('15000'));
        await xyz.mint(admin, toWei('100000'));

        const tokenAddresses = [XYZ, WETH, DAI];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: tokenAddresses,
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

        await crpPool.createPool(toWei('100'), 10, 10);
    });

    it('crpPool should have correct rights set', async () => {
        const response = [];
        const original = Object.values(permissions);

        for (let x = 0; x < original.length; x++) {
            const perm = await crpPool.hasPermission(x);
            response.push(perm);
        }

        assert.sameOrderedMembers(response, original);
    });

    it('With whitelisting on, no one can be an LP initially', async () => {
        let hasPerm = await crpPool.canProvideLiquidity(admin);
        assert.isFalse(hasPerm, 'Admin can provide liquidity');

        hasPerm = await crpPool.canProvideLiquidity(admin2);
        assert.isFalse(hasPerm, 'Admin can provide liquidity');

        hasPerm = await crpPool.canProvideLiquidity(admin3);
        assert.isFalse(hasPerm, 'Admin can provide liquidity');
    });

    it('Only the owner can whitelist an LP', async () => {
        await truffleAssert.reverts(
            crpPool.whitelistLiquidityProvider(admin2, { from: admin3 }),
            'ERR_NOT_CONTROLLER',
        );
    });

    describe('Whitelist admin and admin3', async () => {
        before(async () => {
            await crpPool.whitelistLiquidityProvider(admin);
            await crpPool.whitelistLiquidityProvider(admin3);
        });

        it('Cannot whitelist null', async () => {
            await truffleAssert.reverts(
                crpPool.whitelistLiquidityProvider(ZERO_ADDRESS),
                'ERR_INVALID_ADDRESS',
            );
        });

        it('Allows admin and admin3 to be LPs', async () => {
            let hasPerm = await crpPool.canProvideLiquidity(admin);
            assert.isTrue(hasPerm, 'Admin cannot provide liquidity');

            hasPerm = await crpPool.canProvideLiquidity(admin2);
            assert.isFalse(hasPerm, 'Admin can provide liquidity');

            hasPerm = await crpPool.canProvideLiquidity(admin3);
            assert.isTrue(hasPerm, 'Admin cannot provide liquidity');
        });

        it('Cannot remove if not on whitelist', async () => {
            await truffleAssert.reverts(
                crpPool.removeWhitelistedLiquidityProvider(admin2),
                'ERR_LP_NOT_WHITELISTED',
            );
        });

        it('admin2 cannot join pool', async () => {
            const maxAmountsIn = [toWei('100'), toWei('100'), toWei('100')];

            await truffleAssert.reverts(
                crpPool.joinPool(toWei('1'), maxAmountsIn, { from: admin2 }),
                'ERR_NOT_ON_WHITELIST',
            );

            await truffleAssert.reverts(
                crpPool.joinswapExternAmountIn(weth.address, toWei('100'), toWei('1'), { from: admin2 }),
                'ERR_NOT_ON_WHITELIST',
            );

            await truffleAssert.reverts(
                crpPool.joinswapPoolAmountOut(weth.address, toWei('1'), toWei('100'), { from: admin2 }),
                'ERR_NOT_ON_WHITELIST',
            );
        });

        it('Can remove from whitelist', async () => {
            await crpPool.removeWhitelistedLiquidityProvider(admin3);
            const hasPerm = await crpPool.canProvideLiquidity(admin3);
            assert.isFalse(hasPerm, 'Admin can provide liquidity');
        });
    });
});
