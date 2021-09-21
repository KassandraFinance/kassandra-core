/* global BigInt */

const fc = require('fast-check');
const truffleAssert = require('truffle-assertions');
const { assert } = require('chai');

const AirnodeRrpMock = artifacts.require('AirnodeRrpMock');
const CRPMock = artifacts.require('CRPMock');
const FactoryMock = artifacts.require('FactoryMock');
const PoolMock = artifacts.require('PoolMock');
const StrategyHEIM = artifacts.require('StrategyHEIM');

contract('HEIM Strategy', async (accounts) => {
    const [admin, updater, watcher, nonAdmin] = accounts;

    const {
        toHex,
        toBN,
        toWei,
        padLeft,
        padRight,
    } = web3.utils;

    let strategy;
    let airnodeMock;
    let coreFactoryMock;
    let corePoolMock;
    let crpPoolMock;
    const tokenSymbols = ['xyz', 'weth', 'dai'];

    before(async () => {
        coreFactoryMock = await FactoryMock.new();
        corePoolMock = await PoolMock.new();
        crpPoolMock = await CRPMock.new();
        airnodeMock = await AirnodeRrpMock.new();

        strategy = await StrategyHEIM.new(airnodeMock.address, tokenSymbols);

        await coreFactoryMock.setKacyToken(admin);
        await coreFactoryMock.setKacyMinimum(toBN(toWei('5')).div(toBN('100')));
        await corePoolMock.mockCurrentTokens([updater, watcher, admin]);
        await crpPoolMock.mockCorePool(corePoolMock.address);
        await crpPoolMock.mockCoreFactory(coreFactoryMock.address);
        await airnodeMock.setStrategyAddress(strategy.address);
    });

    describe('Check if functions are protected', () => {
        async function controllerCheck(f, args, addresses, revert) {
            for (let i = 0; i < addresses.length; i++) {
                await truffleAssert.reverts(
                    f(...args, { from: addresses[i] }),
                    revert,
                );
            }
        }

        it('Non-Admin should not change suspect difference', async () => {
            await controllerCheck(
                strategy.setSuspectDiff,
                [10],
                [nonAdmin, watcher, updater],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not change API3 params', async () => {
            const bytes32 = `0x${padLeft('0', 64)}`;

            await controllerCheck(
                strategy.setApi3,
                [bytes32, bytes32, 0, admin],
                [nonAdmin, watcher, updater],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not change CRP Pool', async () => {
            await controllerCheck(
                strategy.setCrpPool,
                [nonAdmin],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not change Core Factory', async () => {
            await controllerCheck(
                strategy.setCoreFactory,
                [nonAdmin],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not change updater', async () => {
            await controllerCheck(
                strategy.setUpdater,
                [nonAdmin],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not change watcher', async () => {
            await controllerCheck(
                strategy.setWatcher,
                [nonAdmin],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not commit a token for addition', async () => {
            await controllerCheck(
                strategy.commitAddToken,
                ['abc', nonAdmin, toWei('10'), toWei('10')],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-Admin should not be able to remove a token', async () => {
            await controllerCheck(
                strategy.removeToken,
                ['weth', nonAdmin],
                [nonAdmin, updater, watcher],
                'ERR_NOT_CONTROLLER',
            );
        });

        it('Non-watchers should not be able to pause the pool', async () => {
            await controllerCheck(
                strategy.pause,
                [],
                [nonAdmin, updater, admin],
                'ERR_NOT_WATCHER',
            );
        });

        it('Non-watchers should not be able to resume the pool', async () => {
            await controllerCheck(
                strategy.resume,
                [],
                [nonAdmin, updater, admin],
                'ERR_NOT_WATCHER',
            );
        });

        it('Non-watchers should not be able to resolve a suspension', async () => {
            await controllerCheck(
                strategy.resolveSuspension,
                [true],
                [nonAdmin, updater, admin],
                'ERR_NOT_WATCHER',
            );
        });

        it('Non-updaters should not be able to make a request', async () => {
            await controllerCheck(
                strategy.makeRequest,
                [],
                [nonAdmin, admin, watcher],
                'ERR_NOT_UPDATER',
            );
        });

        it('Only Airnode should be able to call strategy', async () => {
            const bytes32 = `0x${padLeft('0', 64)}`;

            await controllerCheck(
                strategy.strategy,
                [bytes32, 0, 0],
                [nonAdmin, updater, watcher, admin],
                'Caller not Airnode RRP',
            );
        });
    });

    describe('Should not set parameters to zero', () => {
        const ZERO_ADDRESS = `0x${padLeft('0', 40)}`;

        it('API3 parameters should not be zero', async () => {
            const bytes32 = `0x${padLeft('0', 64)}`;

            await truffleAssert.reverts(
                strategy.setApi3(bytes32, bytes32, 0, ZERO_ADDRESS),
                'ERR_ZERO_ADDRESS',
            );
            await truffleAssert.reverts(
                strategy.setApi3(bytes32, bytes32, 0, admin),
                'ERR_ZERO_ARGUMENT',
            );
        });

        it('crpPool should be a real pool', async () => {
            await truffleAssert.reverts(
                strategy.setCrpPool(ZERO_ADDRESS),
            );
            await truffleAssert.reverts(
                strategy.setCrpPool(admin),
            );
        });

        it('Factory should be a real factory', async () => {
            await truffleAssert.reverts(
                strategy.setCoreFactory(ZERO_ADDRESS),
            );
            await truffleAssert.reverts(
                strategy.setCoreFactory(admin),
            );
        });

        it('Updater should not be the zero address', async () => {
            await truffleAssert.reverts(
                strategy.setUpdater(ZERO_ADDRESS),
                'ERR_ZERO_ADDRESS',
            );
        });

        it('Watcher should not be the zero address', async () => {
            await truffleAssert.reverts(
                strategy.setWatcher(ZERO_ADDRESS),
                'ERR_ZERO_ADDRESS',
            );
        });
    });

    describe('Should correctly set all parameters', () => {
        it('Suspect difference should not be negative', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.integer(-128, 0),
                    async (percent) => {
                        await truffleAssert.reverts(
                            strategy.setSuspectDiff(percent),
                            'ERR_NOT_POSITIVE',
                        );
                    },
                ),
            );
        });

        it('Suspect difference should be positive', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.integer(1, 127),
                    async (percent) => {
                        await strategy.setSuspectDiff(percent);
                        const suspectDiff = await strategy.suspectDiff();
                        assert.strictEqual(suspectDiff.toString(10), toBN(percent).toString(10));
                    },
                ),
            );
        });

        it('Should be able to change API3 params', async () => {
            const bytes32 = `0x${padLeft('1', 64)}`;

            await strategy.setApi3(bytes32, bytes32, 1, admin);
        });

        it('Admin should be able to set the CRPool', async () => {
            await strategy.setCrpPool(crpPoolMock.address);
            const newCRP = await strategy.crpPool();
            assert.strictEqual(newCRP, crpPoolMock.address);
        });

        it('Admin should be able to set the Factory', async () => {
            await strategy.setCoreFactory(coreFactoryMock.address);
            const newCoreFactory = await strategy.coreFactory();
            assert.strictEqual(newCoreFactory, coreFactoryMock.address);
        });

        it('Admin should be able to set updater', async () => {
            await strategy.setUpdater(updater);
            const newUpdater = await strategy.updaterRole();
            assert.strictEqual(newUpdater, updater);
        });

        it('Admin should be able to set watcher', async () => {
            await strategy.setWatcher(watcher);
            const newWatcher = await strategy.watcherRole();
            assert.strictEqual(newWatcher, watcher);
        });
    });

    describe('Testing strategy', () => {
        async function eventEmitted(result, ...args) {
            const resultsOfStrategyHEIM = await truffleAssert.createTransactionResult(strategy, result.tx);
            truffleAssert.eventEmitted(resultsOfStrategyHEIM, ...args);
        }

        async function eventNotEmitted(result, ...args) {
            const resultsOfStrategyHEIM = await truffleAssert.createTransactionResult(strategy, result.tx);
            truffleAssert.eventNotEmitted(resultsOfStrategyHEIM, ...args);
        }

        it('Updater should be able to start request', async () => {
            await strategy.makeRequest({ from: updater });
            const lastRequestId = await airnodeMock.lastRequestId();
            const requestId = await strategy.incomingFulfillments(lastRequestId);
            assert.isTrue(requestId);
        });

        it('Another request should not be initiated while there\'s one ongoing', async () => {
            await truffleAssert.reverts(
                strategy.makeRequest({ from: updater }),
                'ERR_ONLY_ONE_REQUEST_AT_TIME',
            );
        });

        it('Watcher should be able to pause strategy', async () => {
            const tx = await strategy.pause({ from: watcher });

            await truffleAssert.eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('WATCHER_PAUSED'), 64) },
            );
        });

        it('Some functions should not work when strategy is paused', async () => {
            const lastRequestId = await airnodeMock.lastRequestId();

            const tx = await airnodeMock.callStrategy(lastRequestId, 0, 0);
            await truffleAssert.reverts(
                strategy.makeRequest(),
                'Pausable: paused',
            );
            await truffleAssert.reverts(
                strategy.commitAddToken('btc', nonAdmin, 0, 0),
                'Pausable: paused',
            );
            await truffleAssert.reverts(
                strategy.removeToken('btc', nonAdmin),
                'Pausable: paused',
            );

            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_STRATEGY_PAUSED'), 64) },
            );
        });

        it('Watcher should be able to resume strategy', async () => {
            const tx = await strategy.resume({ from: watcher });

            await truffleAssert.eventEmitted(
                tx, 'StrategyResumed',
                { reason: padRight(toHex('WATCHER_RESUMED'), 64) },
            );
        });

        it('Watcher can\'t resolve a suspension that does not exist', async () => {
            await truffleAssert.reverts(
                strategy.resolveSuspension(true, { from: watcher }),
                'ERR_NO_SUSPENDED_REQUEST',
            );
        });

        it('A request we did not make should fail', async () => {
            const bytes32 = `0x${padLeft('1', 64)}`;

            await truffleAssert.reverts(
                airnodeMock.callStrategy(bytes32, 0, 0),
                'ERR_NO_SUCH_REQUEST_MADE',
            );
        });

        it('Bad status code should fail', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.bigInt(BigInt(1), BigInt(1) << BigInt(255)),
                    async (statusCode) => {
                        await strategy.makeRequest({ from: updater });
                        const requestId = await airnodeMock.lastRequestId();
                        const tx = await airnodeMock.callStrategy(requestId, statusCode.toString(), -2);

                        await eventEmitted(
                            tx, 'RequestFailed',
                            { reason: padRight(toHex('ERR_BAD_RESPONSE'), 64) },
                        );
                    },
                ),
            );
        });

        it('If the first bit of the request is not 1 it should fail', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.bigInt(BigInt(0), BigInt(1) << BigInt(254)),
                    async (responseData) => {
                        await strategy.makeRequest({ from: updater });
                        const requestId = await airnodeMock.lastRequestId();
                        const tx = await airnodeMock.callStrategy(requestId, 0, responseData);

                        await eventEmitted(
                            tx, 'RequestFailed',
                            { reason: padRight(toHex('ERR_BAD_RESPONSE'), 64) },
                        );
                    },
                ),
            );
        });

        it('If coin score is zero it should fail', async () => {
            await strategy.makeRequest({ from: updater });

            const responseData = BigInt(1) << BigInt(255);
            const requestId = await airnodeMock.lastRequestId();
            const tx = await airnodeMock.callStrategy(
                requestId, 0, toBN(responseData.toString(16), 16).mul(toBN('-1')),
            );

            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_SCORE_OVERFLOW'), 64) },
            );
        });

        it('If coin score is full it should fail', async () => {
            await strategy.makeRequest({ from: updater });

            const requestId = await airnodeMock.lastRequestId();
            const tx = await airnodeMock.callStrategy(requestId, 0, toBN('-1'));

            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_SCORE_OVERFLOW'), 64) },
            );
        });

        it('First time should suspend the strategy for suspectDiff', async () => {
            await strategy.makeRequest({ from: updater });
            // set a percentage just to be sure
            await strategy.setSuspectDiff(7);

            const responseData = toBN((BigInt(1) << BigInt(255)).toString(16), 16)
                .mul(toBN('-1'))
                .add(toBN('30000'))
                .add(toBN((BigInt(30000) << BigInt(18)).toString(10)));

            const requestId = await airnodeMock.lastRequestId();
            const tx = await airnodeMock.callStrategy(requestId, 0, responseData);

            const lastScores = await strategy.lastScores();
            const pendingScores = await strategy.pendingScores();
            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );
            await eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );

            for (let i = 0; i < lastScores.length; i++) {
                lastScores[i] = lastScores[i].toNumber();
                pendingScores[i] = pendingScores[i].toNumber();
            }

            assert.sameOrderedMembers(lastScores, Array(14).fill(1));
            const testArray = Array(14).fill(1);
            testArray[0] = 30000;
            testArray[1] = 30000;
            assert.sameOrderedMembers(pendingScores, testArray);
        });

        it('Watcher can\'t resume in a suspended state', async () => {
            await truffleAssert.reverts(
                strategy.resume({ from: watcher }),
                'ERR_RESOLVE_SUSPENSION_FIRST',
            );
        });

        it('Watcher should be able to accept a suspended call', async () => {
            const oldPendingScores = await strategy.pendingScores();
            const tx = await strategy.resolveSuspension(true, { from: watcher });

            const lastScores = await strategy.lastScores();
            const pendingScores = await strategy.pendingScores();
            await truffleAssert.eventEmitted(
                tx, 'StrategyResumed',
                { reason: padRight(toHex('ACCEPTED_SUSPENDED_REQUEST'), 64) },
            );

            for (let i = 0; i < lastScores.length; i++) {
                lastScores[i] = lastScores[i].toNumber();
                pendingScores[i] = pendingScores[i].toNumber();
                oldPendingScores[i] = oldPendingScores[i].toNumber();
            }

            assert.sameOrderedMembers(lastScores, oldPendingScores);
            assert.sameOrderedMembers(pendingScores, Array(14).fill(0));
        });

        it('Should suspend the strategy for growing above suspectDiff', async () => {
            const suspectDiff = 7;

            await strategy.makeRequest({ from: updater });
            // set a percentage just to be sure
            await strategy.setSuspectDiff(suspectDiff);

            const aboveSuspectDiff = toBN('30000')
                .mul(toBN(suspectDiff))
                .div(toBN('100'))
                .add(toBN('30000'));

            const responseData = toBN((BigInt(1) << BigInt(255)).toString(16), 16)
                .mul(toBN('-1'))
                .add(aboveSuspectDiff)
                .add(toBN((BigInt(30000) << BigInt(18)).toString(10)));

            const requestId = await airnodeMock.lastRequestId();
            const tx = await airnodeMock.callStrategy(requestId, 0, responseData);

            const pendingScores = await strategy.pendingScores();
            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );
            await eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );

            for (let i = 0; i < pendingScores.length; i++) {
                pendingScores[i] = pendingScores[i].toNumber();
            }

            const testArray = Array(14).fill(1);
            testArray[0] = aboveSuspectDiff.toNumber();
            testArray[1] = 30000;
            assert.sameOrderedMembers(pendingScores, testArray);
        });

        it('Watcher should be able to reject a suspended call', async () => {
            const oldLastScores = await strategy.lastScores();
            const tx = await strategy.resolveSuspension(false, { from: watcher });

            const lastScores = await strategy.lastScores();
            const pendingScores = await strategy.pendingScores();
            await truffleAssert.eventEmitted(
                tx, 'StrategyResumed',
                { reason: padRight(toHex('REJECTED_SUSPENDED_REQUEST'), 64) },
            );

            for (let i = 0; i < lastScores.length; i++) {
                lastScores[i] = lastScores[i].toNumber();
                pendingScores[i] = pendingScores[i].toNumber();
                oldLastScores[i] = oldLastScores[i].toNumber();
            }

            assert.sameOrderedMembers(lastScores, oldLastScores);
            assert.sameOrderedMembers(pendingScores, Array(14).fill(0));
        });

        it('Should suspend the strategy for reducing below suspectDiff', async () => {
            const suspectDiff = 7;

            await strategy.makeRequest({ from: updater });
            // set a percentage just to be sure
            await strategy.setSuspectDiff(suspectDiff);

            const aboveSuspectDiff = toBN('30000')
                .mul(toBN(-suspectDiff))
                .div(toBN('100'))
                .add(toBN('30000'));

            const responseData = toBN((BigInt(1) << BigInt(255)).toString(16), 16)
                .mul(toBN('-1'))
                .add(aboveSuspectDiff)
                .add(toBN((BigInt(30000) << BigInt(18)).toString(10)));

            const requestId = await airnodeMock.lastRequestId();
            const tx = await airnodeMock.callStrategy(requestId, 0, responseData);

            const pendingScores = await strategy.pendingScores();
            await eventEmitted(
                tx, 'RequestFailed',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );
            await eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );

            await strategy.resolveSuspension(false, { from: watcher });

            for (let i = 0; i < pendingScores.length; i++) {
                pendingScores[i] = pendingScores[i].toNumber();
            }

            const testArray = Array(14).fill(1);
            testArray[0] = aboveSuspectDiff.toNumber();
            testArray[1] = 30000;
            assert.sameOrderedMembers(pendingScores, testArray);
        });

        it('The $KACY token should always be the minimum', async () => {
            const suspectDiff = 100;
            let startingWeight = toBN('30000');

            await strategy.setSuspectDiff(suspectDiff);

            while (startingWeight > 0) {
                await strategy.makeRequest({ from: updater });

                let goodDiff = startingWeight
                    .mul(toBN(-suspectDiff + 1))
                    .div(toBN('100'))
                    .add(startingWeight);
                goodDiff = goodDiff.sub(toBN(Number(goodDiff.toString() === startingWeight.toString())));

                const responseData = toBN((BigInt(1) << BigInt(255)).toString(16), 16)
                    .mul(toBN('-1'))
                    .add(toBN('30000'))
                    .add(toBN('30000').shln(18))
                    .add(toBN(goodDiff.shln(36)));

                const requestId = await airnodeMock.lastRequestId();
                const tx = await airnodeMock.callStrategy(requestId, 0, responseData);
                await strategy.resolveSuspension(true, { from: watcher });

                const lastScores = await strategy.lastScores();
                await eventNotEmitted(tx, 'RequestFailed');

                for (let i = 0; i < lastScores.length; i++) {
                    lastScores[i] = lastScores[i].toNumber();
                }

                const testArray = Array(14).fill(1);
                testArray[0] = 30000;
                testArray[1] = 30000;
                assert.sameOrderedMembers(lastScores, testArray);

                startingWeight = goodDiff;
            }
        });
    });

    describe('Adding and removing tokens', () => {
        it('Adding tokens should go fine until 14 are added', async () => {
            const tokens2Add = ['btc', 'doge', 'sol', 'shib', 'api3', 'link', 'usd', 'sushi', 'uni', 'bal', 'axs'];
            const oldTokenSymbols = Array.from(tokenSymbols);

            do {
                const newToken = tokens2Add.pop();
                oldTokenSymbols.push(newToken);

                const commit = await strategy.commitAddToken(newToken, nonAdmin, toWei('10'), toWei('10'));

                const newTokenSymbols = await strategy.tokensSymbols();
                const paused = await strategy.paused();
                await truffleAssert.eventEmitted(
                    commit, 'StrategyPaused',
                    { reason: padRight(toHex('NEW_TOKEN_COMMITTED'), 64) },
                );

                assert.sameOrderedMembers(newTokenSymbols, oldTokenSymbols);
                assert.isTrue(paused);

                const apply = await strategy.applyAddToken();

                const stillPaused = await strategy.paused();
                await truffleAssert.eventEmitted(
                    apply, 'StrategyResumed',
                    { reason: padRight(toHex('NEW_TOKEN_APPLIED'), 64) },
                );

                assert.isFalse(stillPaused);
            } while (tokens2Add.length > 0);
        });

        it('Should fail adding more than 14 tokens', async () => {
            await truffleAssert.reverts(
                strategy.commitAddToken('fail', nonAdmin, toWei('10'), toWei('10')),
                'ERR_MAX_14_TOKENS',
            );
        });

        it('Token should exist to remove', async () => {
            await truffleAssert.reverts(
                strategy.removeToken('nothing', nonAdmin),
                'ERR_TOKEN_SYMBOL_NOT_FOUND',
            );
        });

        it('Existing token should be removed correctly', async () => {
            async function removeToken(symbol2Remove, testArray) {
                const tx = await strategy.removeToken(symbol2Remove, nonAdmin);

                const newTokenSymbols = await strategy.tokensSymbols();
                await truffleAssert.eventEmitted(
                    tx, 'StrategyPaused',
                    { reason: padRight(toHex('REMOVING_TOKEN'), 64) },
                );
                await truffleAssert.eventEmitted(
                    tx, 'StrategyResumed',
                    { reason: padRight(toHex('REMOVED_TOKEN'), 64) },
                );

                assert.sameOrderedMembers(newTokenSymbols, testArray);
            }

            // remove the last one
            const currentTokenSymbols = Array.from(await strategy.tokensSymbols());
            let symbol2Remove = currentTokenSymbols.pop();

            await removeToken(symbol2Remove, currentTokenSymbols);

            // remove the first one
            // eslint-disable-next-line prefer-destructuring
            symbol2Remove = currentTokenSymbols[0];
            currentTokenSymbols[0] = currentTokenSymbols.pop();

            await removeToken(symbol2Remove, currentTokenSymbols);

            // remove in the middle
            // eslint-disable-next-line prefer-destructuring
            symbol2Remove = currentTokenSymbols[5];
            currentTokenSymbols[5] = currentTokenSymbols.pop();

            await removeToken(symbol2Remove, currentTokenSymbols);
        });
    });
});
