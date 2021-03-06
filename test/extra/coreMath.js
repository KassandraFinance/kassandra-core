/* eslint-env es6 */
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');

contract('Test Math', async () => {
    const MAX = web3.utils.toTwosComplement(-1);

    const minValue = new BN('1234');
    const maxValue = new BN('5678');
    const errorDelta = 10 ** -8;

    const { toWei } = web3.utils;

    let coreMath;

    before(async () => {
        coreMath = await KassandraSafeMathMock.deployed();
    });

    describe('Basic Math', () => {
        it('bdiv throws on div by 0', async () => {
            await truffleAssert.reverts(coreMath.bdiv(1, 0), 'ERR_DIV_ZERO');
        });

        it('bmod throws on div by 0', async () => {
            await truffleAssert.reverts(coreMath.bmod(1, 0), 'ERR_MODULO_BY_ZERO');
        });
    });

    describe('max', async () => {
        it('is correctly detected in first argument position', async () => {
            expect(await coreMath.bmax(maxValue, minValue)).to.be.bignumber.equal(maxValue);
        });

        it('is correctly detected in second argument position', async () => {
            expect(await coreMath.bmax(minValue, maxValue)).to.be.bignumber.equal(maxValue);
        });
    });

    describe('min', async () => {
        it('is correctly detected in first argument position', async () => {
            expect(await coreMath.bmin(minValue, maxValue)).to.be.bignumber.equal(minValue);
        });

        it('is correctly detected in second argument position', async () => {
            expect(await coreMath.bmin(maxValue, minValue)).to.be.bignumber.equal(minValue);
        });
    });

    describe('average', async () => {
        function bnAverage(a, b) {
            return a.add(b).divn(2);
        }

        it('is correctly calculated with two odd numbers', async () => {
            const a = new BN('57417');
            const b = new BN('95431');

            expect(await coreMath.baverage(a, b)).to.be.bignumber.equal(bnAverage(a, b));
        });

        it('is correctly calculated with two even numbers', async () => {
            const a = new BN('42304');
            const b = new BN('84346');

            expect(await coreMath.baverage(a, b)).to.be.bignumber.equal(bnAverage(a, b));
        });

        it('is correctly calculated with one even and one odd number', async () => {
            const a = new BN('57417');
            const b = new BN('84346');

            expect(await coreMath.baverage(a, b)).to.be.bignumber.equal(bnAverage(a, b));
        });
    });

    describe('power', () => {
        it('bpow throws on base outside range', async () => {
            await truffleAssert.reverts(coreMath.bpow(0, 2), 'ERR_BPOW_BASE_TOO_LOW');
            await truffleAssert.reverts(coreMath.bpow(MAX, 2), 'ERR_BPOW_BASE_TOO_HIGH');
        });
    });

    describe('Exact math', async () => {
        async function testCommutative(fn, lhs, rhs, expected) {
            expect(await fn(lhs, rhs)).to.be.bignumber.equal(expected);
            expect(await fn(rhs, lhs)).to.be.bignumber.equal(expected);
        }

        // async function testFailsCommutative(fn, lhs, rhs, reason) {
        //     await expectRevert(fn(lhs, rhs), reason);
        //     await expectRevert(fn(rhs, lhs), reason);
        // }

        describe('mul', async () => {
            // This should return 0, because everything is normalized to 1 = 10**18
            // So 1234 * 5678 is actually 1234*10-18 * 5678*10-18 = 7,006,652 * 10**-36 = 0
            it('multiplies correctly', async () => {
                const a = new BN('1234');
                const b = new BN('5678');

                await testCommutative(coreMath.bmul, a, b, '0');
            });

            it('multiplies correctly', async () => {
                const a = new BN('1234');
                const b = new BN('5678');

                await testCommutative(coreMath.bmul, toWei(a), toWei(b), toWei(a.mul(b)));
            });

            it('multiplies by zero correctly', async () => {
                const a = new BN('0');
                const b = new BN('5678');

                await testCommutative(coreMath.bmul, a, b, '0');
            });
        });

        describe('div', async () => {
            it('divides correctly', async () => {
                const a = new BN('5678');
                const b = new BN('5678');

                // Since we are in the "realm" of 10**18,
                //   this returns '1' as Wei, not a.div(b) (regular "1")
                expect(await coreMath.bdiv(a, b)).to.be.bignumber.equal(toWei(a.div(b)));
            });

            it('divides zero correctly', async () => {
                const a = new BN('0');
                const b = new BN('5678');

                expect(await coreMath.bdiv(a, b)).to.be.bignumber.equal('0');
            });

            // This should not return 1; everything is in the realm of 10**18
            it('returns fractional result on non-even division << 10 ** 18', async () => {
                const a = new BN('7000');
                const b = new BN('5678');
                const result = await coreMath.bdiv(a, b);
                const expected = toWei(parseFloat(a / b).toString());
                const diff = expected - result;

                assert.isAtMost(diff, errorDelta);
            });

            it('reverts on division by zero', async () => {
                const a = new BN('5678');
                const b = new BN('0');

                await expectRevert(coreMath.bdiv(a, b), 'ERR_DIV_ZERO');
            });
        });

        describe('mod', async () => {
            describe('modulos correctly', async () => {
                it('when the dividend is smaller than the divisor', async () => {
                    const a = new BN('284');
                    const b = new BN('5678');

                    expect(await coreMath.bmod(a, b)).to.be.bignumber.equal(a.mod(b));
                });

                it('when the dividend is equal to the divisor', async () => {
                    const a = new BN('5678');
                    const b = new BN('5678');

                    expect(await coreMath.bmod(a, b)).to.be.bignumber.equal(a.mod(b));
                });

                it('when the dividend is larger than the divisor', async () => {
                    const a = new BN('7000');
                    const b = new BN('5678');

                    expect(await coreMath.bmod(a, b)).to.be.bignumber.equal(a.mod(b));
                });

                it('when the dividend is a multiple of the divisor', async () => {
                    const a = new BN('17034'); // 17034 == 5678 * 3
                    const b = new BN('5678');

                    expect(await coreMath.bmod(a, b)).to.be.bignumber.equal(a.mod(b));
                });
            });

            it('reverts with a 0 divisor', async () => {
                const a = new BN('5678');
                const b = new BN('0');

                await expectRevert(coreMath.bmod(a, b), 'ERR_MODULO_BY_ZERO');
            });
        });
    });
});
