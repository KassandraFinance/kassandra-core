const hre = require('hardhat');
const { expect, assert } = require('chai');
const { parseEther } = require('ethers/lib/utils');
const { ethers } = require('ethers');

const IConfigurableRightsPoolDef = '/contracts/ConfigurableRightsPool.sol:ConfigurableRightsPool';
const COREPOOL = '/contracts/interfaces/IPool.sol:IPool';

describe('FundProxy', () => {
    let fundProxy;
    let communityStore;
    let manager;
    const multisig = '0xFF56b00bDaEEf52C3EBb81B0efA6e28497305175';
    let PNGtoken;
    let USDCeToken;
    let KACYtoken;
    let poolParams;
    let crpFactory;

    before(async () => {
        const [owner, _manager] = await hre.ethers.getSigners();
        manager = _manager;
        await owner.sendTransaction({
            to: multisig,
            value: hre.ethers.utils.parseEther('50.0'),
        });

        await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [multisig],
        });
        const signer = await hre.ethers.getSigner(multisig);

        const CRPFactory = await hre.ethers.getContractFactory('CRPFactory', {
            signer,
            libraries: {
                RightsManager: '0xFAA21E3EfB22D0e9f536457c51Bcbe02824bceE7',
                SmartPoolManager: '0x4C192c42EA58dcDeAeB24040d10989FEd8772FA9',
            },
        });
        const CoreFactory = await hre.ethers.getContractFactory('Factory', {
            signer,
            libraries: {
                SmartPoolManager: '0x4C192c42EA58dcDeAeB24040d10989FEd8772FA9',
            },
        });
        crpFactory = await CRPFactory.deploy();
        await crpFactory.deployed();
        const coreFactory = await CoreFactory.deploy();
        await coreFactory.deployed();
        await coreFactory.setCRPFactory(crpFactory.address);
        const Token = await hre.ethers.getContractFactory('TToken', signer);

        const png = await Token.deploy('PNG', 'PNG', 18);
        const usdc = await Token.deploy('USDC', 'USDC', 18);
        const kacy = await Token.deploy('KACY', 'KACY', 18);
        coreFactory.setKacyToken(kacy.address);

        await png.mint(manager.address, parseEther('80000'));
        await usdc.mint(manager.address, parseEther('80000'));
        await kacy.mint(manager.address, parseEther('80000'));

        PNGtoken = png.address;
        USDCeToken = usdc.address;
        KACYtoken = kacy.address;

        poolParams = {
            poolTokenSymbol: 'SYMBOL',
            poolTokenName: 'Kassandra Smart Pool Custom Name',
            constituentTokens: [PNGtoken, USDCeToken, KACYtoken],
            tokenBalances: [parseEther('8'), parseEther('4'), parseEther('1')],
            tokenWeights: [parseEther('12'), parseEther('1.5'), parseEther('1.5')],
            swapFee: parseEther('0.003'),
        };

        const CommunityStore = await hre.ethers.getContractFactory('KassandraCommunityStore', signer);
        communityStore = await CommunityStore.deploy();
        await communityStore.deployed();

        const FundProxy = await hre.ethers.getContractFactory('FundProxy', signer);
        fundProxy = await FundProxy.deploy(
            communityStore.address,
            crpFactory.address,
            coreFactory.address,
            '0x84f154A845784Ca37Ae962504250a618EB4859dc',
        );
        await fundProxy.deployed();

        await communityStore.setWriter(fundProxy.address, true);

        await crpFactory.setController(fundProxy.address);

        await communityStore.whitelistToken(PNGtoken, true);
        await communityStore.whitelistToken(USDCeToken, true);

        await png.connect(manager).approve(fundProxy.address, ethers.constants.MaxUint256);
        await usdc.connect(manager).approve(fundProxy.address, ethers.constants.MaxUint256);
        await kacy.connect(manager).approve(fundProxy.address, ethers.constants.MaxUint256);
    });

    it('should not be able to set a manager if sender is not owner', async () => {
        const qtFundsApproved = parseEther('5');

        await expect(fundProxy.connect(manager)
            .setManager(manager.address, qtFundsApproved)).revertedWith('ERR_NOT_CONTROLLER');
    });

    it('should not be able create a fund if the manager has not setted', async () => {
        await expect(fundProxy.connect(manager)
            .newFund(poolParams, parseEther('11'), parseEther('3'), parseEther('10')))
            .revertedWith('ERR_NOT_ALLOWED_TO_CREATE_FUND');
    });

    it('should not be able create a fund if the manager has been set to false', async () => {
        const qtFundsApproved = 0;

        await fundProxy.setManager(manager.address, qtFundsApproved);
        await expect(fundProxy.connect(manager)
            .newFund(poolParams, parseEther('11'), parseEther('3'), parseEther('10')))
            .revertedWith('ERR_NOT_ALLOWED_TO_CREATE_FUND');
    });

    it('should be able to set manager', async () => {
        const qtFundsApproved = ethers.BigNumber.from(5);

        await fundProxy.setManager(manager.address, qtFundsApproved);

        const resultManager = await fundProxy.managers(manager.address);
        assert.strictEqual(resultManager, qtFundsApproved);
    });

    it('should not be able to create a fund if the token is not allowed', async () => {
        await expect(fundProxy.connect(manager)
            .newFund(poolParams, parseEther('11'), parseEther('3'), parseEther('10')))
            .revertedWith('ERR_TOKEN_NOT_ALLOWED');
    });

    it('should be able to create a fund if manager and token is allowed', async () => {
        const supply = parseEther('111');
        const feesToManager = parseEther('3');
        const feesToRefferal = parseEther('1');
        await communityStore.whitelistToken(KACYtoken, true);

        const addressCrp = await fundProxy.connect(manager).callStatic
            .newFund(poolParams, supply, feesToManager, feesToRefferal);
        await fundProxy.connect(manager)
            .newFund(poolParams, supply, feesToManager, feesToRefferal);

        const crp = await hre.ethers.getContractAt(IConfigurableRightsPoolDef, addressCrp);
        const core = await hre.ethers.getContractAt(COREPOOL, await crp.corePool());
        assert.strictEqual(await crp.totalSupply(), supply);
        assert.strictEqual((await communityStore.getPoolInfo(addressCrp))[0], manager.address);
        assert.strictEqual((await communityStore.getPoolInfo(addressCrp))[1], feesToManager);
        assert.strictEqual((await communityStore.getPoolInfo(addressCrp))[2], feesToRefferal);
        assert.strictEqual(await crp.balanceOf(manager.address), supply);
        for (let index = 0; index < poolParams.constituentTokens.length; index++) {
            const token = poolParams.constituentTokens[index];
            const balance = poolParams.tokenBalances[index];
            assert.strictEqual(await core.getBalance(token), balance);
        }
    });

    it('should be able to create a fund if manager and token is allowed', async () => {
        const supply = parseEther('111');
        const feesToManager = parseEther('3');
        const feesToRefferal = parseEther('1');
        const qtAllowedToCreateFunds = await fundProxy.managers(manager.address);

        for (let index = 0; index < qtAllowedToCreateFunds; index++) {
            await fundProxy.connect(manager)
                .newFund(poolParams, supply, feesToManager, feesToRefferal);
        }

        expect(fundProxy.connect(manager)
            .newFund(poolParams, supply, feesToManager, feesToRefferal))
            .revertedWith('ERR_NOT_ALLOWED_TO_CREATE_FUND');
    });
});
