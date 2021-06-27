/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');

const ElasticSupplyPool = artifacts.require('ElasticSupplyPool');
const ESPFactory = artifacts.require('ESPFactory');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');

const verbose = process.env.VERBOSE;

contract('ESPFactory', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);
    const swapFee = 10 ** 15;

    let espFactory;
    let coreFactory;
    let ESPPOOL_ADDRESS;
    let USDC;
    let DAI;
    let dai;
    let usdc;
    let ampl;
    const startWeights = [toWei('12'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('10000')];
    const SYMBOL = 'ESP';
    const LONG_SYMBOL = 'ESP012345678901234567890123456789';
    const NAME = 'Kassandra Pool Token';

    const permissions = {
        canPauseSwapping: false,
        canChangeSwapFee: true,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    before(async () => {
        coreFactory = await Factory.deployed();
        espFactory = await ESPFactory.deployed();
        usdc = await TToken.new('USD Stablecoin', 'USDC', 6);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
        ampl = await TToken.new('Ampleforth', 'AMPL', 9);

        DAI = dai.address;
        USDC = usdc.address;

        // admin balances
        await dai.mint(admin, toWei('15000'));
        await usdc.mint(admin, toWei('100000'));
        await ampl.mint(admin, toWei('1000'));

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [USDC, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        const ESPPOOL = await espFactory.newEsp.call(
            coreFactory.address,
            poolParams,
            permissions,
        );

        await espFactory.newEsp(
            coreFactory.address,
            poolParams,
            permissions,
        );

        const espPool = await ElasticSupplyPool.at(ESPPOOL);

        ESPPOOL_ADDRESS = espPool.address;

        await usdc.approve(ESPPOOL_ADDRESS, MAX);
        await dai.approve(ESPPOOL_ADDRESS, MAX);

        await espPool.createPool(toWei('100'));
    });

    it('CRPFactory should have new espPool registered', async () => {
        if (verbose) {
            console.log(ESPPOOL_ADDRESS);
        }
        const isPoolRegistered = await espFactory.isEsp(ESPPOOL_ADDRESS);

        assert.equal(isPoolRegistered, true, `Expected ${ESPPOOL_ADDRESS} to be registered.`);
    });

    it('CRPFactory should not have random address registered', async () => {
        const isPoolRegistered = await espFactory.isEsp(USDC);
        assert.equal(isPoolRegistered, false, 'Expected not to be registered.');
    });

    it('should be able to create with mismatched start Weights', async () => {
        const badStartWeights = [toWei('12'), toWei('1.5'), toWei('24')];

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [USDC, DAI],
            tokenBalances: startBalances,
            tokenWeights: badStartWeights,
            swapFee,
        };

        await truffleAssert.reverts(
            espFactory.newEsp(
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
            constituentTokens: [USDC, DAI],
            tokenBalances: badStartBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        await truffleAssert.reverts(
            espFactory.newEsp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_START_BALANCES_MISMATCH',
        );
    });

    it('should be able to create with a long symbol', async () => {
        const poolParams = {
            poolTokenSymbol: LONG_SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [USDC, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee,
        };

        espFactory.newEsp(
            coreFactory.address,
            poolParams,
            permissions,
        );
    });

    it('should not be able to create with zero fee', async () => {
        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [USDC, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee: 0,
        };

        await truffleAssert.reverts(
            espFactory.newEsp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_INVALID_SWAP_FEE',
        );
    });

    it('should not be able to create with a fee above the MAX', async () => {
        const invalidSwapFee = '200000000000000000';

        const poolParams = {
            poolTokenSymbol: SYMBOL,
            poolTokenName: NAME,
            constituentTokens: [USDC, DAI],
            tokenBalances: startBalances,
            tokenWeights: startWeights,
            swapFee: invalidSwapFee,
        };

        await truffleAssert.reverts(
            espFactory.newEsp(
                coreFactory.address,
                poolParams,
                permissions,
            ),
            'ERR_INVALID_SWAP_FEE',
        );
    });
});
