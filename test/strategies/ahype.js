/* global BigInt */

const fc = require('fast-check');
const truffleAssert = require('truffle-assertions');
const { assert } = require('chai');

const AirnodeRrpMock = artifacts.require('AirnodeRrpMock');
const CRPMock = artifacts.require('CRPMock');
const FactoryMock = artifacts.require('FactoryMock');
const PoolMock = artifacts.require('PoolMock');
const StrategyAHYPE = artifacts.require('StrategyAHYPE');

contract('HEIM Strategy', async (accounts) => {
    const [admin, updater, watcher, nonAdmin, mockAddr, kacyMock] = accounts;

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
    const tokenSymbols = ['abc', 'def', 'ghi', 'jkl', 'mno', 'pqr', 'stu', 'kacy'];

    before(async () => {
        coreFactoryMock = await FactoryMock.new();
        corePoolMock = await PoolMock.new();
        crpPoolMock = await CRPMock.new();
        airnodeMock = await AirnodeRrpMock.new();

        strategy = await StrategyAHYPE.new(airnodeMock.address, 5700, tokenSymbols);

        await coreFactoryMock.setKacyToken(kacyMock);
        await coreFactoryMock.setKacyMinimum(toBN(toWei('5')).div(toBN('100')));
        const tokenMocks = Array(tokenSymbols.length).fill(mockAddr);
        tokenMocks[tokenSymbols.length - 1] = kacyMock;
        await corePoolMock.mockCurrentTokens(tokenMocks);
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

        it('Constructor should not allow amount of tokens above protocol limit', async () => {
            await truffleAssert.reverts(
                StrategyAHYPE.new(airnodeMock.address, 5700, Array(17).fill('a')),
                'ERR_TOO_MANY_TOKENS',
            );
        });

        it('Constructor should not allow amount of tokens below protocol limit', async () => {
            await truffleAssert.reverts(
                StrategyAHYPE.new(airnodeMock.address, 5700, []),
                'ERR_TOO_FEW_TOKENS',
            );
            await truffleAssert.reverts(
                StrategyAHYPE.new(airnodeMock.address, 5700, ['a']),
                'ERR_TOO_FEW_TOKENS',
            );
        });

        it('Constructor should not allow block period for weight update below minimum', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.integer(0, 5699),
                    async (blocks) => {
                        await truffleAssert.reverts(
                            StrategyAHYPE.new(airnodeMock.address, blocks, tokenSymbols),
                            'ERR_BELOW_MINIMUM',
                        );
                    },
                ),
            );
        });

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
                [admin, bytes32, admin, admin],
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

        it('Non-Admin should not change block period for weight update', async () => {
            await controllerCheck(
                strategy.setWeightUpdateBlockPeriod,
                [900000],
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
            const data = web3.eth.abi.encodeParameter('int256', 0);

            await controllerCheck(
                strategy.strategy,
                [bytes32, data],
                [nonAdmin, updater, watcher, admin],
                'Caller not Airnode RRP',
            );
        });
    });

    describe('Should not set parameters to zero', () => {
        const ZERO_ADDRESS = `0x${padLeft('0', 40)}`;

        it('API3 parameters should not be zero', async () => {
            const bytes32zero = `0x${padLeft('0', 64)}`;
            const bytes32fill = `0x${padLeft('1', 64)}`;

            await truffleAssert.reverts(
                strategy.setApi3(ZERO_ADDRESS, bytes32fill, admin, admin),
                'ERR_ZERO_ADDRESS',
            );
            await truffleAssert.reverts(
                strategy.setApi3(admin, bytes32fill, ZERO_ADDRESS, admin),
                'ERR_ZERO_ADDRESS',
            );
            await truffleAssert.reverts(
                strategy.setApi3(admin, bytes32fill, admin, ZERO_ADDRESS),
                'ERR_ZERO_ADDRESS',
            );
            await truffleAssert.reverts(
                strategy.setApi3(admin, bytes32zero, admin, admin),
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
                    fc.bigInt((BigInt(1) << BigInt(63)) / BigInt(-2), BigInt(0)),
                    async (percent) => {
                        await truffleAssert.reverts(
                            strategy.setSuspectDiff(toBN(percent.toString())),
                            'ERR_NOT_POSITIVE',
                        );
                    },
                ),
            );
        });

        it('Suspect difference should be positive', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.bigInt(BigInt(1), (BigInt(1) << BigInt(63)) - BigInt(1)),
                    async (percent) => {
                        await strategy.setSuspectDiff(toBN(percent.toString()));
                        const suspectDiff = await strategy.suspectDiff();
                        assert.strictEqual(suspectDiff.toString(10), toBN(percent.toString()).toString(10));
                    },
                ),
            );
        });

        it('Should be able to change API3 params', async () => {
            const bytes32 = `0x${padLeft('1', 64)}`;

            await strategy.setApi3(admin, bytes32, admin, admin);
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

        it('Should not save block period for weight update below minimum', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.integer(0, 5699),
                    async (blocks) => {
                        await truffleAssert.reverts(
                            strategy.setWeightUpdateBlockPeriod(blocks),
                            'ERR_BELOW_MINIMUM',
                        );
                    },
                ),
            );
        });

        it('Admin should be able to set block period for weight update', async () => {
            await fc.assert(
                fc.asyncProperty(
                    fc.integer(5700, 100000000000),
                    async (blocks) => {
                        await strategy.setWeightUpdateBlockPeriod(blocks);
                        const weightUpdateBlockPeriod = await strategy.weightUpdateBlockPeriod();
                        assert.strictEqual(weightUpdateBlockPeriod.toString(10), toBN(blocks.toString()).toString(10));
                    },
                ),
            );
        });
    });

    describe('Testing strategy', () => {
        async function eventEmitted(result, ...args) {
            const resultsOfStrategyAHYPE = await truffleAssert.createTransactionResult(strategy, result.tx);
            truffleAssert.eventEmitted(resultsOfStrategyAHYPE, ...args);
        }

        async function eventNotEmitted(result, ...args) {
            const resultsOfStrategyAHYPE = await truffleAssert.createTransactionResult(strategy, result.tx);
            truffleAssert.eventNotEmitted(resultsOfStrategyAHYPE, ...args);
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
            const data = web3.eth.abi.encodeParameter('uint256[]', [0]);

            await truffleAssert.reverts(
                airnodeMock.callStrategy(lastRequestId, data),
                'Pausable: paused',
            );
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

            const data = web3.eth.abi.encodeParameter('int256', 0);
            await truffleAssert.reverts(
                airnodeMock.callStrategy(bytes32, data),
                'ERR_NO_SUCH_REQUEST_MADE',
            );
        });

        it('If coin score is zero it should fail', async () => {
            await strategy.makeRequest({ from: updater });

            const responseData = Array(tokenSymbols.length).fill(0);
            const requestId = await airnodeMock.lastRequestId();
            const data = web3.eth.abi.encodeParameter('int256[]', responseData);
            await airnodeMock.callStrategy(requestId, data);

            await truffleAssert.reverts(
                strategy.updateWeightsGradually(),
                'ERR_SCORE_ZERO',
            );
        });

        it('Should set social scores except for $KACY', async () => {
            await strategy.makeRequest({ from: updater });
            // disable suspectDiff check
            await strategy.setSuspectDiff(toWei('1', 'ether'));

            const responseData = Array(tokenSymbols.length).fill(BigInt(30000));

            const requestId = await airnodeMock.lastRequestId();
            const data = web3.eth.abi.encodeParameter('uint256[]', responseData);
            await airnodeMock.callStrategy(requestId, data);

            await strategy.updateWeightsGradually();

            const lastScores = await strategy.lastScores();
            const pendingScores = await strategy.pendingScores();

            for (let i = 0; i < lastScores.length; i++) {
                lastScores[i] = lastScores[i].toNumber();
                pendingScores[i] = pendingScores[i].toNumber();
            }

            const testArray = Array(tokenSymbols.length).fill(30000);
            testArray[tokenSymbols.length - 1] = 0;
            assert.sameOrderedMembers(pendingScores, Array(pendingScores.length).fill(0));
            assert.sameOrderedMembers(lastScores.slice(0, tokenSymbols.length), testArray);
        });

        it('Should suspend the strategy for growing above suspectDiff', async () => {
            const suspectDiff = 7;

            await strategy.makeRequest({ from: updater });
            // 0.07e18 = 7e16
            await strategy.setSuspectDiff(toBN(suspectDiff).mul(toBN(10).pow(toBN(16))));

            /* add suspectDiff% to one token
             *
             * l = tokenSymbols.length
             * s = suspectDiff
             *
             *       0.95 * x         .95     s
             * ------------------- = ----- + ---
             * (l - 2) * 30000 + x   l - 1   100
             *
             *     -30000 * (l - 2) * (l * s - s + 95)
             * x = -----------------------------------
             *          l * s - 95 * l - s + 190
             */
            const l = BigInt(tokenSymbols.length);
            const s = BigInt(suspectDiff);
            const aboveSuspectDiff = BigInt(1) + ( // rounding will put it below, an extra 1 will be enough
                BigInt(-30000) * (l - BigInt(2)) * (l * s - s + BigInt(95))
            ) / (l * s - BigInt(95) * l - s + BigInt(190));

            const responseData = Array(tokenSymbols.length).fill(30000);
            responseData[0] = aboveSuspectDiff;

            const requestId = await airnodeMock.lastRequestId();
            const data = web3.eth.abi.encodeParameter('uint256[]', responseData);
            await airnodeMock.callStrategy(requestId, data);

            const tx = await strategy.updateWeightsGradually();

            const pendingScores = await strategy.pendingScores();
            await eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );

            for (let i = 0; i < pendingScores.length; i++) {
                pendingScores[i] = pendingScores[i].toNumber();
            }

            const testArray = Array(tokenSymbols.length).fill(30000);
            testArray[0] = Number(aboveSuspectDiff);
            testArray[tokenSymbols.length - 1] = 0;
            assert.sameOrderedMembers(pendingScores.slice(0, tokenSymbols.length), testArray);
        });

        it('Watcher can\'t resume in a suspended state', async () => {
            await truffleAssert.reverts(
                strategy.resume({ from: watcher }),
                'ERR_RESOLVE_SUSPENSION_FIRST',
            );
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
            assert.sameOrderedMembers(pendingScores.slice(0, tokenSymbols.length), Array(tokenSymbols.length).fill(0));
        });

        it('Should suspend the strategy for reducing below suspectDiff', async () => {
            const suspectDiff = 7;

            await strategy.makeRequest({ from: updater });
            // 0.07e18 = 7e16
            await strategy.setSuspectDiff(toBN(suspectDiff).mul(toBN(10).pow(toBN(16))));

            /* remove suspectDiff% to one token
             *
             * l = tokenSymbols.length
             * s = suspectDiff
             *
             *       0.95 * x         .95     s
             * ------------------- = ----- - ---
             * (l - 2) * 30000 + x   l - 1   100
             *
             *     -30000 * (l - 2) * (l * s - s - 95)
             * x = -----------------------------------
             *          l * s + 95 * l - s - 190
             */
            const l = BigInt(tokenSymbols.length);
            const s = BigInt(suspectDiff);
            const belowSuspectDiff = BigInt(-1) + ( // rounding will put it below, an extra 1 will be enough
                BigInt(-30000) * (l - BigInt(2)) * (l * s - s - BigInt(95))
            ) / (l * s + BigInt(95) * l - s - BigInt(190));

            const responseData = Array(tokenSymbols.length).fill(30000);
            responseData[0] = belowSuspectDiff;

            const requestId = await airnodeMock.lastRequestId();
            const data = web3.eth.abi.encodeParameter('uint256[]', responseData);
            await airnodeMock.callStrategy(requestId, data);

            const tx = await strategy.updateWeightsGradually();

            const pendingScores = await strategy.pendingScores();
            await eventEmitted(
                tx, 'StrategyPaused',
                { reason: padRight(toHex('ERR_SUSPECT_REQUEST'), 64) },
            );

            for (let i = 0; i < pendingScores.length; i++) {
                pendingScores[i] = pendingScores[i].toNumber();
            }

            const testArray = Array(tokenSymbols.length).fill(30000);
            testArray[0] = Number(belowSuspectDiff);
            testArray[tokenSymbols.length - 1] = 0;
            assert.sameOrderedMembers(pendingScores.slice(0, tokenSymbols.length), testArray);
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
            assert.sameOrderedMembers(pendingScores.slice(0, tokenSymbols.length), Array(tokenSymbols.length).fill(0));
        });

        it('The $KACY token should always be the minimum', async () => {
            let startingWeight = BigInt(120000);

            // disable suspectDiff check
            await strategy.setSuspectDiff(toWei('1', 'ether'));

            while (startingWeight > 0) {
                await strategy.makeRequest({ from: updater });

                const goodDiff = (startingWeight * BigInt(100 / 2)) / BigInt(100);

                const responseData = Array(tokenSymbols.length).fill(30000);
                responseData[tokenSymbols.length - 1] = goodDiff;

                const requestId = await airnodeMock.lastRequestId();

                const data = web3.eth.abi.encodeParameter('uint256[]', responseData);
                const tx1 = await airnodeMock.callStrategy(requestId, data);
                await eventNotEmitted(tx1, 'RequestFailed');

                const tx2 = await strategy.updateWeightsGradually();
                await eventNotEmitted(tx2, 'StrategyPaused');

                const lastScores = await strategy.lastScores();

                for (let i = 0; i < lastScores.length; i++) {
                    lastScores[i] = lastScores[i].toNumber();
                }

                const testArray = Array(tokenSymbols.length).fill(30000);
                testArray[tokenSymbols.length - 1] = 0;
                assert.sameOrderedMembers(lastScores.slice(0, tokenSymbols.length), testArray);

                startingWeight = goodDiff;
            }
        });

        it('updateWeightsGradually should fail if no data has been saved', async () => {
            await truffleAssert.reverts(
                strategy.updateWeightsGradually(),
                'ERR_NO_PENDING_DATA',
            );
        });

        it('If a call fails watcher should be able to clear it', async () => {
            await strategy.makeRequest({ from: updater });
            const requestId = await airnodeMock.lastRequestId();
            const requestWaiting = await strategy.incomingFulfillments(requestId);

            // request should've been made
            assert.isTrue(requestWaiting);

            await strategy.clearFailedRequest(requestId, { from: watcher });

            // request should've been cleared
            const requestCleared = await strategy.incomingFulfillments(requestId);
            assert.isFalse(requestCleared);

            // updater should be able to request again
            await strategy.makeRequest.call({ from: updater });
        });
    });

    describe('Adding and removing tokens', () => {
        it('Adding tokens should go fine until 16 are added', async () => {
            const tokens2Add = [
                'zyx', 'wvu', 'tsr', 'qpo', 'nml', 'kji', 'hgf', 'edc',
                'ba0', '123', '456', '789', '987', '654', '321', '000',
            ];
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
            } while (tokens2Add.length - tokenSymbols.length > 0);
        });

        it('Should fail adding more than 16 tokens', async () => {
            await truffleAssert.reverts(
                strategy.commitAddToken('fail', nonAdmin, toWei('10'), toWei('10')),
                'ERR_MAX_16_TOKENS',
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
