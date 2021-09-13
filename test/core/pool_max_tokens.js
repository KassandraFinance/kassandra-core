const truffleAssert = require('truffle-assertions');

const Factory = artifacts.require('Factory');
const KassandraConstants = artifacts.require('KassandraConstantsMock');
const Pool = artifacts.require('Pool');
const TToken = artifacts.require('TToken');

contract('Pool', async (accounts) => {
    const admin = accounts[0];

    const { toWei, fromWei } = web3.utils;

    let tokens;
    let extraToken;
    let factory; // factory address
    let pool; // first pool w/ defaults
    let POOL; //   pool address
    let minWeight;
    let maxAssets;
    let maxTotalWeight;

    before(async () => {
        const randomTokenName = () => {
            let name = '';
            for (let i = 0; i < 3; i += 1) {
                name += String.fromCharCode(65 + Math.floor(Math.random * 25));
            }
            return name;
        };

        factory = await Factory.deployed(); // Pool factory

        POOL = await factory.newPool.call();
        await factory.newPool();
        pool = await Pool.at(POOL);

        const consts = await KassandraConstants.deployed();
        maxTotalWeight = await consts.MAX_TOTAL_WEIGHT();
        minWeight = await consts.MIN_WEIGHT();
        maxAssets = await consts.MAX_ASSET_LIMIT();
        maxAssets = Number(fromWei(maxAssets, 'wei')) + 1;

        for (let i = 0; i < maxAssets; i++) {
            const symbol = randomTokenName(i);
            await TToken.new(symbol, symbol, 18);
        }

        extraToken = tokens.pop();

        // Admin balances
        for (let i = 0; i < tokens.length; i++) {
            await tokens[i].mint(admin, toWei('100'));
        }
    });

    describe('Binding Tokens', () => {
        it('Admin approves tokens', async () => {
            const MAX = web3.utils.toTwosComplement(-1);
            await extraToken.approve(POOL, MAX);

            for (let i = 0; i < tokens.length; i++) {
                await tokens[i].approve(POOL, MAX);
            }
        });

        it('Admin binds tokens', async () => {
            assert(
                maxAssets * minWeight <= maxTotalWeight,
                'MAX_TOTAL_WEIGHT is surpassed with maximum amount of tokens',
            );

            for (let i = 0; i < tokens.length; i++) {
                await pool.bind(
                    tokens[i].address,
                    toWei((i + 1) % 3 ? '50' : '70'),
                    toWei(i > tokens.length / 2 ? '0.4' : '1'),
                );
            }

            const total = (4 * (tokens.length / 2 - 1) + 10 * (tokens.length / 2 + 1)) / 10;

            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(total, fromWei(totalDernomWeight));
        });

        it('Fails binding more than maximum tokens', async () => {
            await truffleAssert.reverts(pool.bind(extraToken.address, toWei('50'), toWei('2')), 'ERR_MAX_TOKENS');
        });

        it('Rebind token at a smaller balance', async () => {
            const token = tokens[2];
            // there's a chance of rounding errors here, an improved calculation should be made
            const total = (4 * (tokens.length / 2 - 1) + 10 * (tokens.length / 2 + 1) - 2) / 10;

            await pool.rebind(token.address, toWei('50'), toWei('0.8'));
            const balance = await pool.getBalance(token.address);
            assert.equal(fromWei(balance), 50);

            const adminBalance = await token.balanceOf(admin);
            assert.equal(fromWei(adminBalance), 50);

            const factoryBalance = await token.balanceOf(factory.address);
            assert.equal(fromWei(factoryBalance), 0);

            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(total, fromWei(totalDernomWeight));
        });

        it('Fails gulp on unbound token', async () => {
            await truffleAssert.reverts(pool.gulp(extraToken.address), 'ERR_NOT_BOUND');
        });

        it('Pool can gulp tokens', async () => {
            await tokens[4].transferFrom(admin, POOL, toWei('20'));

            await pool.gulp(tokens[4].address);
            const balance = await pool.getBalance(tokens[4].address);
            assert.equal(fromWei(balance), 70);
        });

        it('Fails swapExactAmountIn with limits', async () => {
            // out token balance, weight = 50, 1
            // in token balance, weight = 50, 0.4
            // spot price ~= 2.500002500002500002
            const lowWeight = tokens.length / 2 + 1;
            const is50Bal = (lowWeight + 1) % 3;
            const inToken = tokens[lowWeight + (is50Bal ? 0 : 1)].address;
            const outToken = tokens[0].address;

            await pool.setPublicSwap(true);
            // should revert if price is above maximum requested
            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    inToken,
                    toWei('1'),
                    outToken,
                    toWei('0'),
                    toWei('0.9'), // < ~2.5
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            // should revert if swap would yield less than requested
            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    inToken,
                    toWei('1'),
                    outToken,
                    toWei('4'), // > ~2.5
                    toWei('3.5'),
                ),
                'ERR_LIMIT_OUT',
            );
            // should revert if price goes above what the user requests after swap
            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    inToken,
                    toWei('1'),
                    outToken,
                    toWei('0'),
                    toWei('2.57028'), // < ~2.570281
                ),
                'ERR_LIMIT_PRICE',
            );
        });

        it('Fails swapExactAmountOut with limits', async () => {
            const lowWeight = tokens.length / 2 + 1;
            const is50Bal = (lowWeight + 1) % 3;
            const inToken = tokens[lowWeight + (is50Bal ? 0 : 1)].address;
            const outToken = tokens[0].address;

            // can't swap out more than a third of the pool in a single transaction
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    inToken,
                    toWei('51'),
                    outToken,
                    toWei('20'), // 1/3 * 50 ~= 16.67
                    toWei('5'),
                ),
                'ERR_MAX_OUT_RATIO',
            );
            // should revert if price is above maximum requested
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    inToken,
                    toWei('51'),
                    outToken,
                    toWei('1'),
                    toWei('0.9'), // < ~2.5
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            // should revert if not enough tokens sent in to swap
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    inToken,
                    toWei('1'), // < ~2.59
                    outToken,
                    toWei('1'),
                    toWei('5'),
                ),
                'ERR_LIMIT_IN',
            );
            // should revert if price goes above what the user requests after swap
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    inToken,
                    toWei('5'),
                    outToken,
                    toWei('1'),
                    toWei('2.68317'), // < ~2.683176
                ),
                'ERR_LIMIT_PRICE',
            );
        });
    });
});
