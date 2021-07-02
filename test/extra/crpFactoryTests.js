/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const KassandraConstants = artifacts.require('KassandraConstantsMock');
const KassandraSafeMath = artifacts.require('KassandraSafeMathMock');
const TToken = artifacts.require('TToken');

contract('CRPFactory', async (accounts) => {
    const admin = accounts[0];
    const { toBN, toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);
    const swapFee = 10 ** 15;

    let crpFactory;
    let coreFactory;
    let crpPool;
    let CRPPOOL_ADDRESS;
    let WETH;
    let DAI;
    let XYZ;
    let weth;
    let dai;
    let xyz;
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = 'KSP';
    const LONG_SYMBOL = '012345678901234567890123456789012';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: false,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    // Can't seem to break it with this - possibly the optimizer is removing unused values?
    // I tried a very large structure (> 256), and still could not break it by passing in a large permissions struct
    // Could still be a problem with optimizer off, or in some way I can't foresee. We have general protection in the
    // Factory against any such shenanigans, by validating the expected calldata size. If it is too big, it reverts.
    const longPermissions = {
        canPauseSwapping: false,
        canChangeSwapFee: false,
        canChangeWeights: false,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
        canMakeMischief: true,
        canOverflowArray: true,
        canBeThreeTooLong: true,
    };

    before(async () => {
        coreFactory = await Factory.deployed();
        crpFactory = await CRPFactory.deployed();
        xyz = await TToken.new('XYZ', 'XYZ', 18);
        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

        WETH = weth.address;
        DAI = dai.address;
        XYZ = xyz.address;

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
            longPermissions, // tolerates extra data at end (calldata still the same size)
        );

        crpPool = await ConfigurableRightsPool.at(CRPPOOL);

        CRPPOOL_ADDRESS = crpPool.address;

        await weth.approve(CRPPOOL_ADDRESS, MAX);
        await dai.approve(CRPPOOL_ADDRESS, MAX);
        await xyz.approve(CRPPOOL_ADDRESS, MAX);

        await crpPool.createPool(toWei('100'));
    });

    it('CRPFactory should have new crpPool registered', async () => {
        console.log(CRPPOOL_ADDRESS);
        const isPoolRegistered = await crpFactory.isCrp(CRPPOOL_ADDRESS);

        assert.equal(isPoolRegistered, true, `Expected ${CRPPOOL_ADDRESS} to be registered.`);
    });

    it('CRPFactory should not have random address registered', async () => {
        const isPoolRegistered = await crpFactory.isCrp(WETH);
        assert.equal(isPoolRegistered, false, 'Expected not to be registered.');
    });

    it('should not be able to create with mismatched start Weights', async () => {
        const badStartWeights = [toWei('12'), toWei('1.5')];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: badStartWeights,
            swapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_START_WEIGHTS_MISMATCH',
        );
    });

    it('should not be able to create with mismatched start Balances', async () => {
        const badStartBalances = [toWei('80000'), toWei('40'), toWei('10000'), toWei('5000')];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: badStartBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_START_BALANCES_MISMATCH',
        );
    });

    it('should still be able to create with a long symbol', async () => {
        const poolParams = {
            poolTokenSymbol: LONG_SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        crpFactory.newCrp(
            coreFactory.address,
            poolParams,
            permissions,
        );
    });

    it('should not be able to create with zero fee', async () => {
        const poolParams = {
            poolTokenSymbol: LONG_SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee: 0,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_INVALID_SWAP_FEE',
        );
    });

    it('should not be able to create with a fee above the MAX', async () => {
        // Max is 10**18 / 10
        // Have to pass it as a string for some reason...
        const invalidSwapFee = '200000000000000000';

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee: invalidSwapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_INVALID_SWAP_FEE',
        );
    });

    it('should not be able to create with a single token', async () => {
        // Max is 10**18 / 10
        // Have to pass it as a string for some reason...
        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [DAI],
            tokenBalances: [toWei('1000')],
            tokenWeights: [toWei('20')],
            swapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_TOO_FEW_TOKENS',
        );
    });

    it('should not be able to create with more than the max tokens', async () => {
        const consts = await KassandraConstants.deployed();
        let maxAssets = await consts.MAX_ASSET_LIMIT();
        maxAssets = Number(toWei(maxAssets, 'wei')) + 1;

        // Max is 10**18 / 10
        // Have to pass it as a string for some reason...
        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: Array(maxAssets).fill(DAI),
            tokenBalances: Array(maxAssets).fill(toWei('1000')),
            tokenWeights: Array(maxAssets).fill(toWei('20')),
            swapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_TOO_MANY_TOKENS',
        );
    });

    it('should not be able to create a pool that doesnt have minimum $KACY', async () => {
        const safeMath = await KassandraSafeMath.deployed();

        const totalWeight = startWeights.reduce((acc, cur) => acc.add(toBN(cur)), toBN(0));
        const normalisedWETH = await safeMath.bdiv(startWeights[1], totalWeight);

        await coreFactory.setKacyToken(WETH);
        await coreFactory.setKacyMinimum(normalisedWETH.add(toBN(100)));

        const poolParams = {
            poolTokenSymbol: LONG_SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        await truffleAssert.reverts(
            crpFactory.newCrp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_MIN_KACY',
        );
    });

    it('should be able to create a pool with minimum $KACY', async () => {
        const safeMath = await KassandraSafeMath.deployed();

        const totalWeight = startWeights.reduce((acc, cur) => acc.add(toBN(cur)), toBN(0));
        const normalisedWETH = await safeMath.bdiv(startWeights[1], totalWeight);

        await coreFactory.setKacyToken(WETH);
        await coreFactory.setKacyMinimum(normalisedWETH.sub(toBN(100)));

        const poolParams = {
            poolTokenSymbol: LONG_SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [XYZ, WETH, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        await crpFactory.newCrp(
            coreFactory.address,
            poolParams,
            permissions,
        );

        await coreFactory.setKacyMinimum('0');
    });
});
