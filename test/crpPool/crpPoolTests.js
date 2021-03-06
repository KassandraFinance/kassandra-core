/* eslint-env es6 */
const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { assert } = require('chai');
const { calcRelativeDiff } = require('../../lib/calc_comparisons');

const ConfigurableRightsPool = artifacts.require('ConfigurableRightsPool');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

const verbose = process.env.VERBOSE;

/*
Tests initial CRP Pool set-up including:
Pool deployment, token binding, balance checks, tokens checks.
*/
contract('crpPoolTests', async (accounts) => {
    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];
    const { toWei, fromWei } = web3.utils;
    const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
    const MAX = web3.utils.toTwosComplement(-1);
    const errorDelta = 10 ** -8;
    // These are the intial settings for newCrp:
    const swapFee = toWei('0.003');
    const startWeights = [toWei('12'), toWei('1.5'), toWei('1.5')];
    const startBalances = [toWei('80000'), toWei('40'), toWei('10000')];
    const SYMBOL = (Math.random() + 1).toString(36).substring(7); // 'KSP';
    const NAME = 'Kassandra Smart Pool Custom Name';

    const permissions = {
        canPauseSwapping: true,
        canChangeSwapFee: true,
        canChangeWeights: true,
        canAddRemoveTokens: true,
        canWhitelistLPs: false,
        canChangeCap: false,
    };

    let corePool;
    let crpPool;
    let WETH;
    let DAI;
    let XYZ;
    let XXX;
    let weth;
    let dai;
    let xyz;
    let xxx;

    before(async () => {
        const coreFactory = await Factory.deployed();
        const crpFactory = await CRPFactory.deployed();
        xyz = await TToken.new('XYZ', 'XYZ', 18);
        weth = await TToken.new('Wrapped Ether', 'WETH', 18);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18);
        xxx = await TToken.new('XXX', 'XXX', 18);

        WETH = weth.address;
        DAI = dai.address;
        XYZ = xyz.address;
        XXX = xxx.address;

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

    it('crpPool should have no core Pool before creation', async () => {
        const corePoolAddr = await crpPool.corePool();
        assert.equal(corePoolAddr, ZERO_ADDRESS);
    });

    it('crpPool should have admin account as controller', async () => {
        const controllerAddr = await crpPool.getController.call();
        assert.equal(controllerAddr, admin);
    });

    it.skip('crpPool should not allow changing controller from non-admin', async () => {
        await truffleAssert.reverts(
            crpPool.setController(user1, { from: user1 }),
            'ERR_NOT_CONTROLLER',
        );
    });

    it.skip('crpPool should not allow changing controller to zero', async () => {
        await truffleAssert.reverts(
            crpPool.setController(ZERO_ADDRESS),
            'ERR_ZERO_ADDRESS',
        );
    });

    it.skip('crpPool should allow changing controller by admin', async () => {
        await crpPool.setController(user1);
        let controllerAddr = await crpPool.getController.call();
        assert.equal(controllerAddr, user1);

        await crpPool.setController(admin);
        controllerAddr = await crpPool.getController.call();
        assert.equal(controllerAddr, admin);
    });

    it('crpPool should have all rights as expected', async () => {
        const response = [];
        const original = Object.values(permissions);

        for (let x = 0; x < original.length; x++) {
            const perm = await crpPool.hasPermission(x);
            response.push(perm);
        }

        assert.sameOrderedMembers(response, original);
    });

    it('Admin should have no initial Tokens', async () => {
        const adminTokensBalance = await crpPool.balanceOf.call(admin);
        assert.equal(adminTokensBalance, toWei('0'));
    });

    it('crpPool should not createPool with 0 Tokens Initial Supply', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('0')),
            'ERR_INIT_SUPPLY_MIN',
        );
    });

    it('crpPool should not createPool with Tokens Initial Supply < MIN', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('10')),
            'ERR_INIT_SUPPLY_MIN',
        );
    });

    it('crpPool should not createPool with Tokens Initial Supply > MAX', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('1000000001')),
            'ERR_INIT_SUPPLY_MAX',
        );
    });

    it('Non controller should not be able to createPool', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100'), { from: user1 }),
            'ERR_NOT_CONTROLLER',
        );
    });

    it('Non controller should not be able to createPool (with time params)', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100', 0, 0), { from: user1 }),
            'ERR_NOT_CONTROLLER',
        );
    });

    it('crpPool should have a core Pool after creation', async () => {
        await crpPool.createPool(toWei('100'));
        const corePoolAddr = await crpPool.corePool();
        assert.notEqual(corePoolAddr, ZERO_ADDRESS);
        corePool = await Pool.at(corePoolAddr);
    });

    it('should not be able to createPool twice', async () => {
        await truffleAssert.reverts(
            crpPool.createPool(toWei('100')),
            'ERR_IS_CREATED',
        );
    });

    it('crpPool should not be able to set the cap without the right', async () => {
        await truffleAssert.reverts(
            crpPool.setCap(toWei('1000')),
            'ERR_CANNOT_CHANGE_CAP',
        );
    });

    it('Core Pool should have matching swap fee', async () => {
        const deployedSwapFee = await corePool.getSwapFee();
        assert.equal(swapFee, deployedSwapFee);
    });

    it('Core Pool should have public swaps enabled', async () => {
        const isPublicSwap = await corePool.isPublicSwap();
        assert.equal(isPublicSwap, true);
    });

    it('Core Pool should have initial token balances', async () => {
        const corePoolAddr = await crpPool.corePool();

        const adminXYZBalance = await xyz.balanceOf.call(admin);
        const corePoolXYZBalance = await xyz.balanceOf.call(corePoolAddr);
        const adminWethBalance = await weth.balanceOf.call(admin);
        const corePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
        const adminDaiBalance = await dai.balanceOf.call(admin);
        const corePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);

        assert.equal(adminXYZBalance, toWei('20000'));
        assert.equal(corePoolXYZBalance, toWei('80000'));
        assert.equal(adminWethBalance, toWei('60'));
        assert.equal(corePoolWethBalance, toWei('40'));
        assert.equal(adminDaiBalance, toWei('5000'));
        assert.equal(corePoolDaiBalance, toWei('10000'));
    });

    it('Core Pool should have initial token weights', async () => {
        const xyzWeight = await corePool.getDenormalizedWeight.call(xyz.address);
        const wethWeight = await corePool.getDenormalizedWeight.call(weth.address);
        const daiWeight = await corePool.getDenormalizedWeight.call(dai.address);

        assert.equal(xyzWeight, toWei('12'));
        assert.equal(wethWeight, toWei('1.5'));
        assert.equal(daiWeight, toWei('1.5'));
    });

    it('Admin should have initial Tokens', async () => {
        const adminTokensBalance = await crpPool.balanceOf.call(admin);
        assert.equal(adminTokensBalance, toWei('100'));
    });

    it('Should not allow joining with partial token list', async () => {
        await truffleAssert.reverts(
            crpPool.joinPool(toWei('1'), [MAX, MAX]),
            'ERR_AMOUNTS_MISMATCH',
        );
    });

    it('Should not allow joining with zero out', async () => {
        await truffleAssert.reverts(
            crpPool.joinPool(toWei('0'), [MAX, MAX, MAX]),
            'ERR_MATH_APPROX',
        );
    });

    it('Should get permissions as an array', async () => {
        const flags = await crpPool.rights();

        assert.sameMembers(
            [flags[0], flags[1], flags[2], flags[3], flags[4], flags[5]],
            [true, true, true, true, false, false],
        );
    });

    it('JoinPool should not revert if smart pool is finalized', async () => {
        const corePoolAddr = await crpPool.corePool();
        let currentPoolBalance = await crpPool.balanceOf.call(admin);
        currentPoolBalance = Decimal(fromWei(currentPoolBalance));
        const previousPoolBalance = currentPoolBalance;
        let previouscorePoolXyzBalance = await xyz.balanceOf.call(corePoolAddr);
        let previouscorePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
        let previouscorePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);
        previouscorePoolXyzBalance = Decimal(fromWei(previouscorePoolXyzBalance));
        previouscorePoolWethBalance = Decimal(fromWei(previouscorePoolWethBalance));
        previouscorePoolDaiBalance = Decimal(fromWei(previouscorePoolDaiBalance));

        const poolAmountOut = '1';
        await crpPool.joinPool(toWei(poolAmountOut), [MAX, MAX, MAX]);

        currentPoolBalance = currentPoolBalance.add(Decimal(poolAmountOut));

        const balance = await crpPool.balanceOf.call(admin);
        const corePoolXYZBalance = await xyz.balanceOf.call(corePoolAddr);
        const corePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
        const corePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);

        // Balances of all tokens increase proportionally to the pool balance
        let balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previouscorePoolWethBalance);
        const currentWethBalance = previouscorePoolWethBalance.add(balanceChange);
        balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previouscorePoolDaiBalance);
        const currentDaiBalance = previouscorePoolDaiBalance.add(balanceChange);
        balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previouscorePoolXyzBalance);
        const currentXyzBalance = previouscorePoolXyzBalance.add(balanceChange);

        assert.equal(fromWei(balance), currentPoolBalance);
        assert.equal(corePoolXYZBalance, toWei(String(currentXyzBalance)));
        assert.equal(corePoolWethBalance, toWei(String(currentWethBalance)));
        assert.equal(corePoolDaiBalance, toWei(String(currentDaiBalance)));
    });

    it('Should get the RightsManager address', async () => {
        const rightsManager = await crpPool.getRightsManagerVersion();
        assert.isTrue(rightsManager !== 0);

        if (verbose) {
            console.log(rightsManager);
        }
    });

    it('Should get the SmartPoolManager address', async () => {
        const smartPoolManager = await crpPool.getSmartPoolManagerVersion();
        assert.isTrue(smartPoolManager !== 0);

        if (verbose) {
            console.log(smartPoolManager);
        }
    });

    it('JoinPool should revert if user does not have allowance to join pool', async () => {
        await truffleAssert.reverts(
            crpPool.joinPool(toWei('1'), [MAX, MAX, MAX], { from: user1 }),
            'ERR_TOKEN_BAD_CALLER',
        );
    });

    it('Fails calling any swap on unbound token', async () => {
        await truffleAssert.reverts(
            crpPool.joinswapExternAmountIn(XXX, toWei('2.5'), toWei('0')),
            'ERR_NOT_BOUND',
        );
        await truffleAssert.reverts(
            crpPool.joinswapPoolAmountOut(XXX, toWei('2.5'), MAX),
            'ERR_NOT_BOUND',
        );
        await truffleAssert.reverts(
            crpPool.exitswapPoolAmountIn(XXX, toWei('2.5'), toWei('0')),
            'ERR_NOT_BOUND',
        );
        await truffleAssert.reverts(
            crpPool.exitswapExternAmountOut(XXX, toWei('2.5'), MAX),
            'ERR_NOT_BOUND',
        );
    });

    it('tAo = exitswapPoolAmountIn(exitswapExternAmountOut(tAo))', async () => {
        // From Balancer Core
        const tAo = '1';
        const pAi = await crpPool.exitswapExternAmountOut.call(DAI, toWei(tAo), MAX);
        const calculatedtAo = await crpPool.exitswapPoolAmountIn.call(DAI, String(pAi), toWei('0'));

        const expected = Decimal(tAo);
        const actual = fromWei(calculatedtAo);
        const relDif = calcRelativeDiff(expected, actual);

        if (verbose) {
            console.log(`pAi: ${pAi})`);
            console.log('tAo');
            console.log(`expected: ${expected})`);
            console.log(`actual  : ${actual})`);
            console.log(`relDif  : ${relDif})`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);
    });

    it('pAo = joinswapExternAmountIn(joinswapPoolAmountOut(pAo))', async () => {
        // From Balancer Core
        const pAo = 1;
        const tAi = await crpPool.joinswapPoolAmountOut.call(WETH, toWei(String(pAo)), MAX);
        const calculatedPAo = await crpPool.joinswapExternAmountIn.call(WETH, String(tAi), toWei('0'));

        const expected = Decimal(pAo);
        const actual = fromWei(calculatedPAo);
        const relDif = calcRelativeDiff(expected, actual);

        if (verbose) {
            console.log(`tAi: ${tAi})`);
            console.log('pAo');
            console.log(`expected: ${expected})`);
            console.log(`actual  : ${actual})`);
            console.log(`relDif  : ${relDif})`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);
    });

    it('should not allow exiting with an amount mismatch', async () => {
        await truffleAssert.reverts(
            crpPool.exitPool(toWei('1'), [toWei('2.5')]),
            'ERR_AMOUNTS_MISMATCH',
        );
    });

    it('should not allow exiting with zero amount in', async () => {
        await truffleAssert.reverts(
            crpPool.exitPool(toWei('0'), [toWei('0'), toWei('0'), toWei('0')]),
            'ERR_MATH_APPROX',
        );
    });

    it('should exitpool', async () => {
        const corePoolAddr = await crpPool.corePool();
        const poolAmountIn = '99';

        let currentPoolBalance = await crpPool.balanceOf.call(admin);
        let previouscorePoolXyzBalance = await xyz.balanceOf.call(corePoolAddr);
        let previouscorePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
        let previouscorePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);
        currentPoolBalance = Decimal(fromWei(currentPoolBalance));
        previouscorePoolXyzBalance = Decimal(fromWei(previouscorePoolXyzBalance));
        previouscorePoolWethBalance = Decimal(fromWei(previouscorePoolWethBalance));
        previouscorePoolDaiBalance = Decimal(fromWei(previouscorePoolDaiBalance));
        const previousPoolBalance = Decimal(currentPoolBalance);

        await crpPool.exitPool(toWei(poolAmountIn), [toWei('0'), toWei('0'), toWei('0')]);

        currentPoolBalance = currentPoolBalance.sub(Decimal(poolAmountIn));

        const poolBalance = await crpPool.balanceOf.call(admin);
        const corePoolXYZBalance = await xyz.balanceOf.call(corePoolAddr);
        const corePoolWethBalance = await weth.balanceOf.call(corePoolAddr);
        const corePoolDaiBalance = await dai.balanceOf.call(corePoolAddr);

        // Balances of all tokens increase proportionally to the pool balance
        let balanceChange = (Decimal(poolAmountIn).div(previousPoolBalance)).mul(previouscorePoolWethBalance);
        const currentWethBalance = previouscorePoolWethBalance.sub(balanceChange);
        balanceChange = (Decimal(poolAmountIn).div(previousPoolBalance)).mul(previouscorePoolDaiBalance);
        const currentDaiBalance = previouscorePoolDaiBalance.sub(balanceChange);
        balanceChange = (Decimal(poolAmountIn).div(previousPoolBalance)).mul(previouscorePoolXyzBalance);
        const currentXyzBalance = previouscorePoolXyzBalance.sub(balanceChange);

        let relDif = calcRelativeDiff(currentXyzBalance, fromWei(corePoolXYZBalance));
        assert.isAtMost(relDif.toNumber(), errorDelta);
        relDif = calcRelativeDiff(currentDaiBalance, fromWei(corePoolDaiBalance));
        assert.isAtMost(relDif.toNumber(), errorDelta);
        relDif = calcRelativeDiff(currentWethBalance, fromWei(corePoolWethBalance));
        assert.isAtMost(relDif.toNumber(), errorDelta);
        assert.equal(fromWei(poolBalance), currentPoolBalance);
    });

    it('should not allow exitpool without enough tokens', async () => {
        await truffleAssert.reverts(
            crpPool.exitPool(toWei('50'), [toWei('0'), toWei('0'), toWei('0')]),
        );
    });

    describe('SPToken interactions', () => {
        it('Token descriptors', async () => {
            const name = await crpPool.name();
            assert.equal(name, NAME); // 'Kassandra Smart Pool-' + SYMBOL);

            const symbol = await crpPool.symbol();
            assert.equal(symbol, SYMBOL);

            const decimals = await crpPool.decimals();
            assert.equal(decimals, 18);
        });

        it('Token allowances', async () => {
            await crpPool.approve(user1, toWei('50'));
            let allowance = await crpPool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 50);

            await crpPool.increaseApproval(user1, toWei('50'));
            allowance = await crpPool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 100);

            await crpPool.decreaseApproval(user1, toWei('50'));
            allowance = await crpPool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 50);

            await crpPool.decreaseApproval(user1, toWei('100'));
            allowance = await crpPool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 0);
        });

        it('Token transfers', async () => {
            await truffleAssert.reverts(
                crpPool.transferFrom(user2, admin, toWei('10')),
                'ERR_TOKEN_BAD_CALLER',
            );

            await crpPool.transferFrom(admin, user2, toWei('1'));
            await crpPool.approve(user2, toWei('10'));
            await crpPool.transferFrom(admin, user2, toWei('1'), { from: user2 });
            await crpPool.transfer(admin, toWei('0.5'), { from: user2 });

            // Test error message (fall through to math; catch underflow)
            await truffleAssert.reverts(
                crpPool.transfer(admin, toWei('10000'), { from: user2 }),
            );
        });
    });
});
