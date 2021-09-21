/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');
const { time } = require('@openzeppelin/test-helpers');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const TToken = artifacts.require('TToken');
const Pool = artifacts.require('Pool');

const verbose = process.env.VERBOSE;

contract('configurableAddRemoveTokens - join/exit after add', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let crpPool;
    let WETH;
    let DAI;
    let XYZ;
    let ABC;
    let weth;
    let dai;
    let xyz;
    let abc;
    let asd;
    let applyAddTokenValidBlock;

    // These are the intial settings for newCrp:
    const swapFee = 10 ** 15;
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const addTokenTimeLockInBlocks = 10;
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
        ABC = abc.address;

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

        await crpPool.createPool(toWei('100'), 10, 10);
        await crpPool.setStrategy(admin);
    });

    describe('JoinExit after add', () => {
        it('Controller should be able to commitAddToken', async () => {
            const block = await web3.eth.getBlock('latest');
            applyAddTokenValidBlock = block.number + addTokenTimeLockInBlocks;

            if (verbose) {
                console.log(`Block commitAddToken for ABC: ${block.number}`);
                console.log(`applyAddToken valid block: ${applyAddTokenValidBlock}`);
            }

            await crpPool.commitAddToken(ABC, toWei('10000'), toWei('1.5'));

            // original has no ABC
            const corePoolAddr = await crpPool.corePool();
            const corePool = await Pool.at(corePoolAddr);
            const corePoolAbcBalance = await abc.balanceOf.call(corePoolAddr);
            const adminAbcBalance = await abc.balanceOf.call(admin);

            await truffleAssert.reverts(
                corePool.getDenormalizedWeight.call(abc.address),
                'ERR_NOT_BOUND',
            );

            assert.equal(corePoolAbcBalance, toWei('0'));
            assert.equal(adminAbcBalance, toWei('100000'));
        });

        it('Controller should be able to applyAddToken', async () => {
            let block = await web3.eth.getBlock('latest');
            while (block.number <= applyAddTokenValidBlock) {
                if (verbose) {
                    console.log(`Waiting; block: ${block.number}`);
                }

                await time.advanceBlock();
                block = await web3.eth.getBlock('latest');
            }

            const corePoolAddr = await crpPool.corePool();
            const corePool = await Pool.at(corePoolAddr);

            let adminKSPBalance = await crpPool.balanceOf.call(admin);
            let adminAbcBalance = await abc.balanceOf.call(admin);
            let corePoolAbcBalance = await abc.balanceOf.call(corePoolAddr);

            assert.equal(adminKSPBalance, toWei('100'));
            assert.equal(adminAbcBalance, toWei('100000'));
            assert.equal(corePoolAbcBalance, toWei('0'));

            await crpPool.applyAddToken();

            adminKSPBalance = await crpPool.balanceOf.call(admin);
            adminAbcBalance = await abc.balanceOf.call(admin);
            corePoolAbcBalance = await abc.balanceOf.call(corePoolAddr);
            const corePoolXYZBalance = await xyz.balanceOf.call(corePoolAddr);
            const corePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
            const corePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);

            // KSP Balance should go from 100 to 110 since total weight went from 15 to 16.5
            assert.equal(adminKSPBalance, toWei('110'));
            assert.equal(adminAbcBalance, toWei('90000'));
            assert.equal(corePoolAbcBalance, toWei('10000'));
            assert.equal(corePoolXYZBalance, toWei('80000'));
            assert.equal(corePoolWethBalance, toWei('40'));
            assert.equal(corePoolDaiBalance, toWei('10000'));

            const xyzWeight = await corePool.getDenormalizedWeight.call(xyz.address);
            const wethWeight = await corePool.getDenormalizedWeight.call(weth.address);
            const daiWeight = await corePool.getDenormalizedWeight.call(dai.address);
            const abcWeight = await corePool.getDenormalizedWeight.call(abc.address);

            assert.equal(xyzWeight, toWei('12'));
            assert.equal(wethWeight, toWei('1.5'));
            assert.equal(daiWeight, toWei('1.5'));
            assert.equal(abcWeight, toWei('1.5'));
        });

        it('Should be able to join/exit pool after addition', async () => {
            const poolAmountOut = '1';
            await crpPool.joinPool(toWei(poolAmountOut), [MAX, MAX, MAX, MAX]);

            const poolAmountIn = '99';
            await crpPool.exitPool(toWei(poolAmountIn), [toWei('0'), toWei('0'), toWei('0'), toWei('0')]);
        });
    });

    describe('JoinExit after remove', () => {
        it('Should be able to remove token', async () => {
            // Remove DAI
            await crpPool.removeToken(DAI);

            const corePoolAddr = await crpPool.corePool();
            const corePool = await Pool.at(corePoolAddr);

            // Verify gone
            await truffleAssert.reverts(
                corePool.getDenormalizedWeight.call(dai.address),
                'ERR_NOT_BOUND',
            );
        });

        it('Should be able to join/exit pool after removal', async () => {
            const poolAmountOut = '1';
            await crpPool.joinPool(toWei(poolAmountOut), [MAX, MAX, MAX]);

            const poolAmountIn = '10';
            await crpPool.exitPool(toWei(poolAmountIn), [toWei('0'), toWei('0'), toWei('0')]);
        });
    });
});
