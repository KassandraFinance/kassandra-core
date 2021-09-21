/* eslint-env es6 */

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');

contract('Remove all tokens', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let WETH;
    let DAI;
    let XYZ;
    let weth;
    let dai;
    let xyz;
    let abc;
    let asd;

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
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    before(async () => {
        /*
        Uses deployed core Factory & CRPFactory.
        Deploys new test tokens - XYZ, WETH, DAI, ABC, ASD
        Mints test tokens for Admin user (account[0])
        CRPFactory creates new CRP.
        Admin approves CRP for MAX
        newCrp call with configurableAddRemoveTokens set to true
        */
        const coreFactory = await Factory.deployed();
        const crpFactory = await CRPFactory.deployed();
        xyz = await TToken.new('XYZ', 'XYZ', 18);
        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
        abc = await TToken.new('ABC', 'ABC', 18);
        asd = await TToken.new('ASD', 'ASD', 18);

        WETH = weth.address;
        DAI = dai.address;
        XYZ = xyz.address;

        // admin balances
        await weth.mint(admin, toWei('100'));
        await dai.mint(admin, toWei('15000'));
        await xyz.mint(admin, toWei('100000'));
        await abc.mint(admin, toWei('100000'));
        await asd.mint(admin, toWei('100000'));

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
        await abc.approve(CRPPOOL_ADDRESS, MAX);
        await asd.approve(CRPPOOL_ADDRESS, MAX);

        await crpPool.createPool(toWei('100'));
        await crpPool.setStrategy(admin);
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

    it('Should be able to remove all tokens', async () => {
        // It now has ABC, XYZ, and WETH
        await crpPool.removeToken(DAI);
        await crpPool.removeToken(XYZ);
        await crpPool.removeToken(WETH);
    });
});
