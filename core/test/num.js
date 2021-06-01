const truffleAssert = require('truffle-assertions');

const TMath = artifacts.require('TMath');

contract('TMath', async () => {
    const MAX = web3.utils.toTwosComplement(-1);

    describe('Math', () => {
        let tmath;
        before(async () => {
            tmath = await TMath.deployed();
        });

        it('bpow throws on base outside range', async () => {
            await truffleAssert.reverts(tmath.calc_bpow(0, 2), 'ERR_BPOW_BASE_TOO_LOW');
            await truffleAssert.reverts(tmath.calc_bpow(MAX, 2), 'ERR_BPOW_BASE_TOO_HIGH');
        });
    });
});
