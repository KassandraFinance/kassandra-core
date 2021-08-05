const truffleAssert = require('truffle-assertions');

const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const KassandraConstants = artifacts.require('KassandraConstantsMock');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

contract('Factory', async (accounts) => {
    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const user2 = accounts[2];
    const { toBN, toWei, fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    describe('Factory', () => {
        let factory;
        let pool;
        let POOL;
        let WETH;
        let DAI;
        let exitFee;
        let one;

        before(async () => {
            const constants = await KassandraConstants.deployed();
            one = await constants.ONE();
            exitFee = await constants.EXIT_FEE();

            factory = await Factory.deployed();
            const weth = await TToken.new('Wrapped Ether', 'WETH', 18);
            const dai = await TToken.new('Dai Stablecoin', 'DAI', 18);

            WETH = weth.address;
            DAI = dai.address;

            // admin balances
            await weth.mint(admin, toWei('5'));
            await dai.mint(admin, toWei('200'));

            // nonAdmin balances
            await weth.mint(nonAdmin, toWei('1'), { from: admin });
            await dai.mint(nonAdmin, toWei('50'), { from: admin });

            POOL = await factory.newPool.call(); // this works fine in clean room
            await factory.newPool();
            pool = await Pool.at(POOL);

            await weth.approve(POOL, MAX);
            await dai.approve(POOL, MAX);

            await weth.approve(POOL, MAX, { from: nonAdmin });
            await dai.approve(POOL, MAX, { from: nonAdmin });
        });

        it('isPool on non pool returns false', async () => {
            const isPool = await factory.isPool(admin);
            assert.isFalse(isPool);
        });

        it('isPool on pool returns true', async () => {
            const isPool = await factory.isPool(POOL);
            assert.isTrue(isPool);
        });

        it('fails nonAdmin calls collect', async () => {
            await truffleAssert.reverts(factory.collect(nonAdmin, { from: nonAdmin }), 'ERR_NOT_CONTROLLER');
        });

        it('admin collects fees', async () => {
            await pool.bind(WETH, toWei('5'), toWei('5'));
            await pool.bind(DAI, toWei('200'), toWei('5'));

            await pool.finalize();

            await pool.joinPool(toWei('10'), [MAX, MAX], { from: nonAdmin });
            await pool.exitPool(toWei('10'), [toWei('0'), toWei('0')], { from: nonAdmin });

            await factory.collect(POOL);

            const adminBalance = await pool.balanceOf(admin);
            // start balance + fee from exitPool of 10 tokens above
            assert.equal(
                fromWei(adminBalance),
                fromWei(
                    exitFee
                        .mul(toBN(toWei('10')))
                        .div(one)
                        .add(toBN(toWei('100')))
                        .toString(),
                ),
            );
        });

        it('nonadmin cant change $KACY address', async () => {
            await truffleAssert.reverts(factory.setKacyToken(WETH, { from: nonAdmin }), 'ERR_NOT_CONTROLLER');
        });

        it('admin changes $KACY address', async () => {
            await factory.setKacyToken(WETH);
            const kacy = await factory.kacyToken();
            assert.equal(kacy, WETH);
        });

        it('$KACY address must be valid token', async () => {
            await truffleAssert.reverts(
                factory.setKacyToken(admin),
            );
        });

        it('nonadmin cant change minimum $KACY', async () => {
            await truffleAssert.reverts(
                factory.setKacyMinimum(toBN(20).mul(one).div(toBN(100)), { from: nonAdmin }),
                'ERR_NOT_CONTROLLER',
            );
        });

        it('admin changes minimum $KACY', async () => {
            const minimum = toBN(20).mul(one).div(toBN(100));
            await factory.setKacyMinimum(minimum);
            const minimumKacy = await factory.minimumKacy();
            assert.equal(minimumKacy.toString(), minimum.toString());
        });

        it('minimum $KACY should be less than 100%', async () => {
            await truffleAssert.reverts(
                factory.setKacyMinimum(toWei('1')), 'ERR_NOT_VALID_PERCENTAGE',
            );
        });

        it('nonadmin cant change crpFactory', async () => {
            await truffleAssert.reverts(factory.setCRPFactory(admin, { from: nonAdmin }), 'ERR_NOT_CONTROLLER');
        });

        it('admin changes crpFactory', async () => {
            const newCRP = await CRPFactory.new();
            await factory.setCRPFactory(newCRP.address);
            const crpFactory = await factory.crpFactory();
            assert.equal(crpFactory, newCRP.address);
        });

        it('crpFactory should be valid', async () => {
            await truffleAssert.reverts(
                factory.setCRPFactory(admin),
            );
        });

        it('nonadmin cant set controller address', async () => {
            await truffleAssert.reverts(factory.setController(nonAdmin, { from: nonAdmin }), 'ERR_NOT_CONTROLLER');
        });

        it('admin changes controller address', async () => {
            await factory.setController(user2);
            const blab = await factory.getController();
            assert.equal(blab, user2);
        });
    });
});
