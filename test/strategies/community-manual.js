const { assert, expect } = require('chai');
const { parseEther } = require('ethers/lib/utils');
const hardhat = require('hardhat');

const { ethers, waffle } = hardhat;
const { loadFixture } = waffle;
const verbose = process.env.VERBOSE;

describe('Community Manual Strategy', () => {
    async function deployFixture() {
        const [CommunityStore, ManualStrategy, CRPMock, CoreMock] = await Promise.all([
            ethers.getContractFactory('KassandraCommunityStore'),
            ethers.getContractFactory('KassandraManualStrategy'),
            ethers.getContractFactory('CRPMock'),
            ethers.getContractFactory('PoolMock'),
        ]);
        const storeContract = await CommunityStore.deploy();
        const crpMock = await CRPMock.deploy();
        const coreMock = await CoreMock.deploy();
        await Promise.all([
            storeContract.deployed(),
            crpMock.deployed(),
            coreMock.deployed(),
        ]);
        await crpMock.mockCorePool(coreMock.address);
        const strategyContract = await ManualStrategy.deploy(storeContract.address, 0, 0);
        await strategyContract.deployed();

        const [owner, manager] = await ethers.getSigners();

        await storeContract.setWriter(owner.address, true);
        await storeContract.setManager(crpMock.address, manager.address);

        return {
            strategyContract,
            storeContract,
            crpMock,
            coreMock,
            owner,
            manager,
        };
    }

    async function deployTestToken() {
        const TToken = await ethers.getContractFactory('TToken');
        const testToken = await TToken.deploy('Test', 'TEST', 18);
        await testToken.deployed();

        return testToken;
    }

    it('Admin functions must be protected', async () => {
        const { strategyContract, manager } = await loadFixture(deployFixture);

        await expect(
            strategyContract.connect(manager).setNormalizedWeightForTokenManipulation(0),
        ).revertedWith(
            'ERR_NOT_CONTROLLER',
        );

        await expect(
            strategyContract.connect(manager).setMaxWeigthChangePerBlock(0),
        ).revertedWith(
            'ERR_NOT_CONTROLLER',
        );

        await expect(
            strategyContract.connect(manager).setDataStore(manager.address),
        ).revertedWith(
            'ERR_NOT_CONTROLLER',
        );
    });

    it('Management function must only be used by pool manager', async () => {
        const { strategyContract, crpMock } = await loadFixture(deployFixture);
        const [, , notManager] = await ethers.getSigners();

        await expect(
            strategyContract.connect(notManager).commitAddToken(crpMock.address, ethers.constants.AddressZero, 0, 0),
        ).revertedWith(
            'ERR_NOT_POOL_MANAGER',
        );

        await expect(
            strategyContract.connect(notManager).applyAddToken(crpMock.address),
        ).revertedWith(
            'ERR_NOT_POOL_MANAGER',
        );

        await expect(
            strategyContract.connect(notManager).removeToken(crpMock.address, ethers.constants.AddressZero),
        ).revertedWith(
            'ERR_NOT_POOL_MANAGER',
        );

        await expect(
            strategyContract.connect(notManager).updateWeightsGradually(crpMock.address, [0], 0, 0),
        ).revertedWith(
            'ERR_NOT_POOL_MANAGER',
        );
    });

    it('Should not commit a token not on the whitelist', async () => {
        const { strategyContract, crpMock, manager } = await loadFixture(deployFixture);

        await expect(
            strategyContract.connect(manager).commitAddToken(
                crpMock.address,
                ethers.constants.AddressZero,
                50,
                50,
            ),
        ).revertedWith('ERR_TOKEN_NOT_WHITELISTED');
    });

    it('Manager can commit a new token', async () => {
        const {
            strategyContract,
            storeContract,
            crpMock,
            coreMock,
            manager,
            owner,
        } = await loadFixture(deployFixture);

        const testToken = await deployTestToken();
        const third = ethers.utils.parseEther('10');
        const two = ethers.utils.parseEther('2');

        await Promise.all([
            storeContract.connect(owner).whitelistToken(testToken.address, true),
            strategyContract.connect(owner).setNormalizedWeightForTokenManipulation(ethers.utils.parseEther('0.0625')),
            coreMock.bind(coreMock.address, 0, third),
            coreMock.bind(manager.address, 0, third),
            coreMock.bind(strategyContract.address, 0, third),
        ]);

        console.log((await strategyContract.normalizedWeightForTokenManipulation()).toString());

        await expect(
            strategyContract.connect(manager).commitAddToken(crpMock.address, testToken.address, two, two),
        ).not.reverted;
    });

    it('Manager can apply adding a token', async () => {
        const {
            strategyContract,
            storeContract,
            crpMock,
            coreMock,
            manager,
            owner,
        } = await loadFixture(deployFixture);

        const testToken = await deployTestToken();
        const two = ethers.utils.parseEther('2');
        const third = ethers.utils.parseEther('10');

        await Promise.all([
            storeContract.connect(owner).whitelistToken(testToken.address, true),
            strategyContract.connect(owner).setNormalizedWeightForTokenManipulation(ethers.utils.parseEther('0.0625')),
            coreMock.bind(coreMock.address, 0, third),
            coreMock.bind(manager.address, 0, third),
            coreMock.bind(strategyContract.address, 0, third),
            testToken.mint(manager.address, two),
            testToken.connect(manager).approve(strategyContract.address, two),
        ]);

        await strategyContract.connect(manager).commitAddToken(crpMock.address, testToken.address, two, two);

        await expect(
            strategyContract.connect(manager).applyAddToken(crpMock.address),
        ).not.reverted;
        assert.equal((await testToken.balanceOf(crpMock.address)).toString(), two.toString());
    });

    it('Manager can remove a token', async () => {
        const {
            strategyContract,
            crpMock,
            coreMock,
            manager,
        } = await loadFixture(deployFixture);

        const testToken = await deployTestToken();
        const quarter = ethers.utils.parseEther('10');
        const two = ethers.utils.parseEther('2');

        await Promise.all([
            strategyContract.setNormalizedWeightForTokenManipulation(ethers.utils.parseEther('0.25')),
            coreMock.bind(coreMock.address, 0, quarter),
            coreMock.bind(manager.address, 0, quarter),
            coreMock.bind(strategyContract.address, 0, quarter),
            coreMock.bind(testToken.address, two, quarter),
            testToken.mint(crpMock.address, two),
        ]);

        await expect(
            strategyContract.connect(manager).removeToken(crpMock.address, testToken.address),
        ).not.reverted;
        assert.equal((await testToken.balanceOf(manager.address)).toString(), two.toString());
    });
});
