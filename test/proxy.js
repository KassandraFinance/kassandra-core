const { assert } = require('chai');
const { parseEther } = require('ethers/lib/utils');
const hre = require('hardhat');
const web3 = require('web3');

const verbose = process.env.VERBOSE;

describe('HermesProxy', () => {
    const feesManager = hre.ethers.BigNumber.from('20000000000000000');
    const feesRefferal = hre.ethers.BigNumber.from('10000000000000000');
    let proxy;
    let signer;
    let crpPoolAddr = 0;
    let corePool;
    let wizard;
    let refferal;
    const multisig = '0xFF56b00bDaEEf52C3EBb81B0efA6e28497305175';
    const yyAVAXonAAVE = '0xaAc0F2d0630d1D09ab2B5A400412a4840B866d95';
    const yyUSDCEonPlatypus = '0xb126FfC190D0fEBcFD7ca73e0dCB60405caabc90';
    const yyPNGonPangolin = '0x19707F26050Dfe7eb3C1b36E49276A088cE98752';
    const PNGtoken = '0x60781C2586D68229fde47564546784ab3fACA982';
    const USDCeToken = '0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664';
    const KACYtoken = '0xf32398dae246C5f672B52A54e9B413dFFcAe1A44';
    const wAVAXtoken = '0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7';

    before(async () => {
        const [owner, _wizard, _refferal] = await hre.ethers.getSigners();
        wizard = _wizard;
        refferal = _refferal;
        await owner.sendTransaction({
            to: multisig,
            value: hre.ethers.utils.parseEther('50.0'),
        });

        await hre.network.provider.request({
            method: 'hardhat_impersonateAccount',
            params: [multisig],
        });
        signer = await hre.ethers.getSigner(multisig);
        const CommunityStore = await hre.ethers.getContractFactory('KassandraCommunityStore', signer);
        const communityStore = await CommunityStore.deploy();
        await communityStore.deployed();
        const HermesProxy = await hre.ethers.getContractFactory('HermesProxy', signer);
        proxy = await HermesProxy.deploy(wAVAXtoken, communityStore.address);
        await proxy.deployed();

        const CRPFactory = await hre.ethers.getContractFactory('CRPFactory', {
            signer,
            libraries: {
                RightsManager: '0xFAA21E3EfB22D0e9f536457c51Bcbe02824bceE7',
                SmartPoolManager: '0x4C192c42EA58dcDeAeB24040d10989FEd8772FA9',
            },
        });
        const crpFactory = await CRPFactory.attach('0x958c051B55a173e393af696EcB4C4FF3D6C13930');

        const yyAVAX = await hre.ethers.getContractAt('YakStrategyV2Payable', yyAVAXonAAVE, signer);
        const yyPNG = await hre.ethers.getContractAt('YakStrategyV2', yyPNGonPangolin, signer);
        const yyUSDCe = await hre.ethers.getContractAt('YakStrategyV2', yyUSDCEonPlatypus, signer);

        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const KACY = await Token.attach(KACYtoken);

        await PNG.approve(yyPNGonPangolin, web3.utils.toTwosComplement(-1), { from: multisig });
        await USDCe.approve(yyUSDCEonPlatypus, web3.utils.toTwosComplement(-1), { from: multisig });

        const PNGBalance = await PNG.balanceOf(multisig);
        const usdcBalance = await USDCe.balanceOf(multisig);

        await yyAVAX.deposit({ value: '2000000000000000000', from: multisig });
        await yyUSDCe.deposit(usdcBalance.div(2), { from: multisig });
        await yyPNG.deposit(PNGBalance.div(2), { from: multisig });

        // 1632,454742000000000000
        // 278470,034314
        // 14096,935336835402336797

        const tokens = [
            yyAVAXonAAVE, // yyAVAX
            yyUSDCEonPlatypus, // yyUSDC.e
            yyPNGonPangolin, // yyPNG
            KACYtoken, // KACY
        ];

        const [
            yyAVAXbalance,
            yyUSDCebalance,
            yyTraderJOEbalance,
            kacyBalance,
        ] = await Promise.all([
            yyAVAX.balanceOf(multisig),
            yyUSDCe.balanceOf(multisig),
            yyPNG.balanceOf(multisig),
            KACY.balanceOf(multisig),
        ]);

        const balances = [
            yyAVAXbalance.div(2),
            yyUSDCebalance.div(2),
            yyTraderJOEbalance.div(2),
            kacyBalance.div(2),
        ];

        const denorm = [
            '2000000000000000000',
            '2000000000000000000',
            '2000000000000000000',
            '2000000000000000000',
        ];

        const poolParams = {
            poolTokenSymbol: 'This string 100% has more than 32 characters',
            poolTokenName: 'This string 100% has more than 32 characters',
            constituentTokens: tokens,
            tokenBalances: balances,
            tokenWeights: denorm,
            swapFee: hre.ethers.utils.parseEther('0.003'),
        };

        const rights = {
            canPauseSwapping: true,
            canChangeSwapFee: true,
            canChangeWeights: true,
            canAddRemoveTokens: true,
            canWhitelistLPs: false,
            canChangeCap: false,
        };

        crpPoolAddr = await crpFactory.callStatic.newCrp(
            '0x878Fa1EF7D9C7453EA493C2424449d32f1DBd846',
            poolParams,
            rights,
            { from: multisig },
        );

        await crpFactory.newCrp(
            '0x878Fa1EF7D9C7453EA493C2424449d32f1DBd846',
            poolParams,
            rights,
            { from: multisig },
        );

        await communityStore.setWriter(wizard.address, true);
        await communityStore.connect(wizard).setManager(crpPoolAddr, wizard.address, feesManager, feesRefferal);

        const CRP = await hre.ethers.getContractFactory('ConfigurableRightsPool', {
            signer,
            libraries: {
                RightsManager: '0xFAA21E3EfB22D0e9f536457c51Bcbe02824bceE7',
                SmartPoolManager: '0x4C192c42EA58dcDeAeB24040d10989FEd8772FA9',
            },
        });
        const crpPool = await CRP.attach(crpPoolAddr);

        for (let i = 0; i < tokens.length; i++) {
            const token = await Token.attach(tokens[i]);
            await token.approve(
                crpPoolAddr,
                web3.utils.toTwosComplement(-1),
                { from: multisig },
            );
        }

        await crpPool['createPool(uint256)'](hre.ethers.utils.parseEther('1000.0'), { from: multisig });
        await crpPool.setExitFeeCollector('0xB8897C7f08D085Ded52A938785Df63C79BBE9c25');

        corePool = await crpPool.corePool();

        await proxy.setTokenWrapper(
            crpPool.address,
            corePool,
            wAVAXtoken,
            yyAVAXonAAVE,
            'deposit()',
            'withdraw(uint256)',
            'getSharesForDepositTokens(uint256)',
        );

        await proxy.setTokenWrapper(
            crpPool.address,
            corePool,
            USDCeToken,
            yyUSDCEonPlatypus,
            'deposit(uint256)',
            'withdraw(uint256)',
            'getSharesForDepositTokens(uint256)',
        );

        await proxy.setTokenWrapper(
            crpPool.address,
            corePool,
            PNGtoken,
            yyPNGonPangolin,
            'deposit(uint256)',
            'withdraw(uint256)',
            'getSharesForDepositTokens(uint256)',
        );

        const triCrypto = await Token.attach(crpPoolAddr);
        const wAVAX = await Token.attach(wAVAXtoken);

        await yyAVAX.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await yyPNG.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await yyUSDCe.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await KACY.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await wAVAX.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await PNG.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await USDCe.approve(proxy.address, web3.utils.toTwosComplement(-1));
        await triCrypto.approve(proxy.address, web3.utils.toTwosComplement(-1));
    });

    it.skip('Exchange is valid', async () => {
        const exchangeA = await proxy.exchangeRate(corePool, wAVAXtoken);
        const exchangeP = await proxy.exchangeRate(corePool, USDCeToken);
        const exchangeU = await proxy.exchangeRate(corePool, PNGtoken);
        const exchangeK = await proxy.exchangeRate(corePool, KACYtoken);

        if (verbose) {
            console.log(exchangeA.toString());
            console.log(exchangeP.toString());
            console.log(exchangeU.toString());
            console.log(exchangeK.toString());
        }

        assert.isTrue(exchangeA.gt(hre.ethers.utils.parseEther('1.0')), 'Less AVAX than expected');
        assert.isTrue(exchangeP.gt(hre.ethers.utils.parseEther('1.0')), 'Less PNG than expected');
        assert.isTrue(exchangeU.gt(hre.ethers.utils.parseEther('1.0')), 'Less USDC than expected');
        assert.isTrue(exchangeK.eq(hre.ethers.utils.parseEther('1.0')), 'KACY amount should be the same');
    });

    it('Can withdraw the underlying tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            yyAVAXonAAVE,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            yyPNGonPangolin,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            KACYtoken,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());
        }

        assert.isTrue(balanceTriCrypto.sub(balanceTriCrypton).eq(hre.ethers.utils.parseEther('200.0')), 'Wrong amount');
        assert.isTrue(balanceAn.gt(balanceA), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balancePn.gt(balanceP), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceUn.gt(balanceU), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceKn.gt(balanceK), 'Amount of KACY is less than expected');
    });

    it('Can withdraw the unwrapped tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            wAVAXtoken,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            PNGtoken,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        await proxy.exitswapPoolAmountIn(
            crpPoolAddr,
            USDCeToken,
            hre.ethers.utils.parseEther('50.0'),
            0,
        );

        const balanceAn = await signer.getBalance();
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
        }

        assert.isTrue(balanceTriCrypto.sub(balanceTriCrypton).eq(hre.ethers.utils.parseEther('150.0')), 'Wrong amount');
        assert.isTrue(balanceAn.gt(balanceA), 'Amount of AVAX is less than expected');
        assert.isTrue(balancePn.gt(balanceP), 'Amount of PNG is less than expected');
        assert.isTrue(balanceUn.gt(balanceU), 'Amount of USD is less than expected');
    });

    it.skip('Can withdraw the underlying tokens', async () => {
        const CorePool = await hre.ethers.getContractFactory('Pool', signer);
        const core = await CorePool.attach(corePool);
        const poolBalanceA = await core.getBalance(yyAVAXonAAVE);
        const poolBalanceP = await core.getBalance(yyPNGonPangolin);
        const poolBalanceU = await core.getBalance(yyUSDCEonPlatypus);
        const poolBalanceK = await core.getBalance(KACYtoken);

        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        let balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            yyAVAXonAAVE,
            poolBalanceA.div(10),
            balanceTriCrypto,
        );

        balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            yyPNGonPangolin,
            poolBalanceP.div(10),
            balanceTriCrypto,
        );

        balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            poolBalanceU.div(10),
            balanceTriCrypto,
        );

        balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            KACYtoken,
            poolBalanceK.div(10),
            balanceTriCrypto,
        );

        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());

            console.log(balanceAn.sub(balanceA).toString());
            console.log(poolBalanceA.div(10).toString());
            console.log(balancePn.sub(balanceP).toString());
            console.log(poolBalanceP.div(10).toString());
            console.log(balanceUn.sub(balanceU).toString());
            console.log(poolBalanceU.div(10).toString());
            console.log(balanceKn.sub(balanceK).toString());
            console.log(poolBalanceK.div(10).toString());
        }

        assert.isTrue(balanceAn.sub(balanceA).eq(poolBalanceA.div(10)), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balancePn.sub(balanceP).eq(poolBalanceP.div(10)), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceUn.sub(balanceU).eq(poolBalanceU.div(10)), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceKn.sub(balanceK).eq(poolBalanceK.div(10)), 'Amount of KACY is less than expected');
    });

    it.skip('Can withdraw the unwrapped tokens', async () => {
        const CorePool = await hre.ethers.getContractFactory('Pool', signer);
        const core = await CorePool.attach(corePool);
        const poolBalanceA = await core.getBalance(yyAVAXonAAVE);
        const poolBalanceP = await core.getBalance(yyPNGonPangolin);
        const poolBalanceU = await core.getBalance(yyUSDCEonPlatypus);

        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        let balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            wAVAXtoken,
            poolBalanceA.div(10),
            balanceTriCrypto,
        );

        balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            PNGtoken,
            poolBalanceP.div(10),
            balanceTriCrypto,
        );

        balanceTriCrypto = await triCrypto.balanceOf(multisig);
        await proxy.exitswapExternAmountOut(
            crpPoolAddr,
            USDCeToken,
            poolBalanceU.div(10),
            balanceTriCrypto,
        );

        const balanceAn = await signer.getBalance();
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());

            console.log(balanceAn.sub(balanceA).toString());
            console.log(poolBalanceA.div(10).toString());
            console.log(balancePn.sub(balanceP).toString());
            console.log(poolBalanceP.div(10).toString());
            console.log(balanceUn.sub(balanceU).toString());
            console.log(poolBalanceU.div(10).toString());
        }

        assert.isTrue(balanceAn.sub(balanceA).eq(poolBalanceA.div(10)), 'Amount of AVAX is less than expected');
        assert.isTrue(balancePn.sub(balanceP).eq(poolBalanceP.div(10)), 'Amount of PNG is less than expected');
        assert.isTrue(balanceUn.sub(balanceU).eq(poolBalanceU.div(10)), 'Amount of USD is less than expected');
    });

    it('Can withdraw with multiple tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const usdce = await Token.attach(USDCeToken);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const kacy = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceU = await usdce.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceK = await kacy.balanceOf(multisig);
        const balanceA = await signer.getBalance();
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceU.toString());
            console.log(balanceP.toString());
            console.log(balanceK.toString());
            console.log(balanceA.toString());
        }

        await proxy.exitPool(
            crpPoolAddr,
            hre.ethers.utils.parseEther('500.0'),
            [wAVAXtoken, USDCeToken, yyPNGonPangolin, KACYtoken],
            [0, 0, 0, 0],
        );

        const balanceUn = await usdce.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceKn = await kacy.balanceOf(multisig);
        const balanceAn = await signer.getBalance();
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);

        if (verbose) {
            console.log(balanceUn.toString());
            console.log(balancePn.toString());
            console.log(balanceKn.toString());
            console.log(balanceAn.toString());
        }

        assert.isTrue(balanceTriCrypto.sub(balanceTriCrypton).eq(hre.ethers.utils.parseEther('500.0')), 'Wrong amount');
        assert.isTrue(balanceAn.gt(balanceA), 'Amount of AVAX is less than expected');
        assert.isTrue(balanceUn.gt(balanceU), 'Amount of USD is less than expected');
        assert.isTrue(balancePn.gt(balanceP), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceKn.gt(balanceK), 'Amount of KACY is less than expected');
    });

    it('Can join with underlying tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyAVAXonAAVE,
            balanceA.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyPNGonPangolin,
            balanceP.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            balanceU.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            KACYtoken,
            balanceK.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1')).add(totalAmountSendTriCrypto.mul(feesRefferal).div(parseEther('1')));

        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = await triCrypto.balanceOf(wizard.address);
        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());

            console.log(balanceA.sub(balanceAn).toString());
            console.log(balanceA.div(100).toString());
            console.log(balanceP.sub(balancePn).toString());
            console.log(balanceP.div(100).toString());
            console.log(balanceU.sub(balanceUn).toString());
            console.log(balanceU.div(100).toString());
            console.log(balanceK.sub(balanceKn).toString());
            console.log(balanceK.div(100).toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.gt(balanceTriCrypto), 'Amount of Tri Crypto is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).eq(balanceA.div(100)), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balanceP.sub(balancePn).eq(balanceP.div(100)), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceU.sub(balanceUn).eq(balanceU.div(100)), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceK.sub(balanceKn).eq(balanceK.div(100)), 'Amount of KACY is less than expected');
    });

    it('Can join with underlying tokens and sends invest fees to referral and manager', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoManager = await triCrypto.balanceOf(wizard.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyAVAXonAAVE,
            balanceA.div(100),
            0,
            refferal.address,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyPNGonPangolin,
            balanceP.div(100),
            0,
            refferal.address,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            balanceU.div(100),
            0,
            refferal.address,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            KACYtoken,
            balanceK.div(100),
            0,
            refferal.address,
        );

        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1'));
        const feesToRefferal = totalAmountSendTriCrypto.mul(
            feesRefferal,
        ).div(parseEther('1'));

        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoManager);
        const balanceTriCryptor = await triCrypto.balanceOf(refferal.address);
        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());

            console.log(balanceA.sub(balanceAn).toString());
            console.log(balanceA.div(100).toString());
            console.log(balanceP.sub(balancePn).toString());
            console.log(balanceP.div(100).toString());
            console.log(balanceU.sub(balanceUn).toString());
            console.log(balanceU.div(100).toString());
            console.log(balanceK.sub(balanceKn).toString());
            console.log(balanceK.div(100).toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isAtMost(feesToRefferal.sub(balanceTriCryptor).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.gt(balanceTriCrypto), 'Amount of Tri Crypto is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).eq(balanceA.div(100)), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balanceP.sub(balancePn).eq(balanceP.div(100)), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceU.sub(balanceUn).eq(balanceU.div(100)), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceK.sub(balanceKn).eq(balanceK.div(100)), 'Amount of KACY is less than expected');
    });

    it('Can join with unwrapped tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const wAVAX = await Token.attach(wAVAXtoken);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceWA = await wAVAX.balanceOf(multisig);
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceWA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            wAVAXtoken,
            hre.ethers.utils.parseEther('0.02'),
            0,
            hre.ethers.constants.AddressZero,
            { value: hre.ethers.utils.parseEther('0.02') },
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            wAVAXtoken,
            balanceWA.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            PNGtoken,
            balanceP.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            USDCeToken,
            balanceU.div(100),
            0,
            hre.ethers.constants.AddressZero,
        );
        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1')).add(totalAmountSendTriCrypto.mul(feesRefferal).div(parseEther('1')));
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceAn = await signer.getBalance();
        const balanceWAn = await wAVAX.balanceOf(multisig);
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balanceWAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());

            console.log(balanceA.sub(balanceAn).toString());
            console.log(hre.ethers.utils.parseEther('0.02').toString());
            console.log(balanceP.sub(balancePn).toString());
            console.log(balanceP.div(100).toString());
            console.log(balanceU.sub(balanceUn).toString());
            console.log(balanceU.div(100).toString());
            console.log(balanceWA.sub(balanceWAn).toString());
            console.log(balanceWA.div(100).toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.gt(balanceTriCrypto), 'Amount of Tri Crypto is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).gt(hre.ethers.utils.parseEther('0.02')), 'AVAX is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).lt(hre.ethers.utils.parseEther('0.04')), 'AVAX is less than expected');
        assert.isTrue(balanceP.sub(balancePn).eq(balanceP.div(100)), 'Amount of PNG is less than expected');
        assert.isTrue(balanceU.sub(balanceUn).eq(balanceU.div(100)), 'Amount of USD is less than expected');
        assert.isTrue(balanceWA.sub(balanceWAn).eq(balanceWA.div(100)), 'Amount of wAVAX is less than expected');
    });

    it('Can join with unwrapped tokens and send invest fees to refferal and manager', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const wAVAX = await Token.attach(wAVAXtoken);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceWA = await wAVAX.balanceOf(multisig);
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const balanceTriCryptoRefferal = await triCrypto.balanceOf(refferal.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceWA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            wAVAXtoken,
            hre.ethers.utils.parseEther('0.02'),
            0,
            refferal.address,
            { value: hre.ethers.utils.parseEther('0.02') },
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            wAVAXtoken,
            balanceWA.div(100),
            0,
            refferal.address,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            PNGtoken,
            balanceP.div(100),
            0,
            refferal.address,
        );

        await proxy.joinswapExternAmountIn(
            crpPoolAddr,
            USDCeToken,
            balanceU.div(100),
            0,
            refferal.address,
        );
        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1'));
        const feesToRefferal = totalAmountSendTriCrypto.mul(
            feesRefferal,
        ).div(parseEther('1'));

        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceTriCryptor = (await triCrypto.balanceOf(refferal.address)).sub(balanceTriCryptoRefferal);
        const balanceAn = await signer.getBalance();
        const balanceWAn = await wAVAX.balanceOf(multisig);
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balanceWAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());

            console.log(balanceA.sub(balanceAn).toString());
            console.log(hre.ethers.utils.parseEther('0.02').toString());
            console.log(balanceP.sub(balancePn).toString());
            console.log(balanceP.div(100).toString());
            console.log(balanceU.sub(balanceUn).toString());
            console.log(balanceU.div(100).toString());
            console.log(balanceWA.sub(balanceWAn).toString());
            console.log(balanceWA.div(100).toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isAtMost(feesToRefferal.sub(balanceTriCryptor).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.gt(balanceTriCrypto), 'Amount of Tri Crypto is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).gt(hre.ethers.utils.parseEther('0.02')), 'AVAX is less than expected');
        assert.isTrue(balanceA.sub(balanceAn).lt(hre.ethers.utils.parseEther('0.04')), 'AVAX is less than expected');
        assert.isTrue(balanceP.sub(balancePn).eq(balanceP.div(100)), 'Amount of PNG is less than expected');
        assert.isTrue(balanceU.sub(balanceUn).eq(balanceU.div(100)), 'Amount of USD is less than expected');
        assert.isTrue(balanceWA.sub(balanceWAn).eq(balanceWA.div(100)), 'Amount of wAVAX is less than expected');
    });

    it('Can join with underlying tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyAVAXonAAVE,
            hre.ethers.utils.parseEther('1.0'),
            balanceA.div(2),
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyPNGonPangolin,
            hre.ethers.utils.parseEther('1.0'),
            balanceP.div(2),
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            hre.ethers.utils.parseEther('1.0'),
            balanceU.div(2),
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            KACYtoken,
            hre.ethers.utils.parseEther('1.0'),
            balanceK.div(2),
            hre.ethers.constants.AddressZero,
        );

        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1')).add(totalAmountSendTriCrypto.mul(feesRefferal).div(parseEther('1')));
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.sub(balanceTriCrypto).eq(hre.ethers.utils.parseEther('4.0')), 'Wrong amount');
        assert.isTrue(balanceA.gt(balanceAn), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balanceP.gt(balancePn), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceU.gt(balanceUn), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceK.gt(balanceKn), 'Amount of KACY is less than expected');
    });

    it('Can join with underlying tokens and send invest fees to refferal and manager', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const yyAVAX = await Token.attach(yyAVAXonAAVE);
        const yyPNG = await Token.attach(yyPNGonPangolin);
        const yyUSDCe = await Token.attach(yyUSDCEonPlatypus);
        const KACY = await Token.attach(KACYtoken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await yyAVAX.balanceOf(multisig);
        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await yyUSDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const balanceTriCryptoRefferal = await triCrypto.balanceOf(refferal.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
            console.log(balanceK.toString());
        }

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyAVAXonAAVE,
            hre.ethers.utils.parseEther('1.0'),
            balanceA.div(2),
            refferal.address,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyPNGonPangolin,
            hre.ethers.utils.parseEther('1.0'),
            balanceP.div(2),
            refferal.address,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            yyUSDCEonPlatypus,
            hre.ethers.utils.parseEther('1.0'),
            balanceU.div(2),
            refferal.address,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            KACYtoken,
            hre.ethers.utils.parseEther('1.0'),
            balanceK.div(2),
            refferal.address,
        );

        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1'));
        const feesToRefferal = totalAmountSendTriCrypto.mul(
            feesRefferal,
        ).div(parseEther('1'));

        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceTriCryptor = (await triCrypto.balanceOf(refferal.address)).sub(balanceTriCryptoRefferal);
        const balanceAn = await yyAVAX.balanceOf(multisig);
        const balancePn = await yyPNG.balanceOf(multisig);
        const balanceUn = await yyUSDCe.balanceOf(multisig);
        const balanceKn = await KACY.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
            console.log(balanceKn.toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isAtMost(feesToRefferal.sub(balanceTriCryptor).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.sub(balanceTriCrypto).eq(hre.ethers.utils.parseEther('4.0')), 'Wrong amount');
        assert.isTrue(balanceA.gt(balanceAn), 'Amount of yyAVAX is less than expected');
        assert.isTrue(balanceP.gt(balancePn), 'Amount of yyPNG is less than expected');
        assert.isTrue(balanceU.gt(balanceUn), 'Amount of yyUSD is less than expected');
        assert.isTrue(balanceK.gt(balanceKn), 'Amount of KACY is less than expected');
    });

    it('Can join with unwrapped tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const wAVAX = await Token.attach(wAVAXtoken);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceWA = await wAVAX.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceWA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        // await proxy.joinswapPoolAmountOut(
        //     crpPoolAddr,
        //     wAVAXtoken,
        //     hre.ethers.utils.parseEther('1.0'),
        //     hre.ethers.utils.parseEther('1.0'),
        //     { value: hre.ethers.utils.parseEther('1.0') },
        // );

        // await proxy.joinswapPoolAmountOut(
        //     crpPoolAddr,
        //     wAVAXtoken,
        //     hre.ethers.utils.parseEther('1.0'),
        //     balanceWA.div(2),
        // );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            PNGtoken,
            hre.ethers.utils.parseEther('1.0'),
            balanceP.div(2),
            hre.ethers.constants.AddressZero,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            USDCeToken,
            hre.ethers.utils.parseEther('1.0'),
            balanceU.div(2),
            hre.ethers.constants.AddressZero,
        );
        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1')).add(totalAmountSendTriCrypto.mul(feesRefferal).div(parseEther('1')));
        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceAn = await signer.getBalance();
        const balanceWAn = await wAVAX.balanceOf(multisig);
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balanceWAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.sub(balanceTriCrypto).eq(hre.ethers.utils.parseEther('2.0')), 'Wrong amount');
        // assert.isTrue(balanceA.lt(hre.ethers.utils.parseEther('1.0')), 'Amount of AVAX is more than expected');
        // assert.isTrue(balanceA.gt(balanceAn), 'Amount of AVAX is less than expected');
        // assert.isTrue(balanceWA.gt(balanceWAn), 'Amount of wAVAX is less than expected');
        assert.isTrue(balanceP.gt(balancePn), 'Amount of PNG is less than expected');
        assert.isTrue(balanceU.gt(balanceUn), 'Amount of USD is less than expected');
    });

    it('Can join with unwrapped tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const wAVAX = await Token.attach(wAVAXtoken);
        const PNG = await Token.attach(PNGtoken);
        const USDCe = await Token.attach(USDCeToken);
        const triCrypto = await Token.attach(crpPoolAddr);

        const balanceA = await signer.getBalance();
        const balanceP = await PNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceWA = await wAVAX.balanceOf(multisig);
        const balanceTriCrypto = await triCrypto.balanceOf(multisig);
        const balanceTriCryptoWizard = await triCrypto.balanceOf(wizard.address);
        const balanceTriCryptoRefferal = await triCrypto.balanceOf(refferal.address);
        const supplyTriCrypto = await triCrypto.totalSupply();

        if (verbose) {
            console.log(balanceA.toString());
            console.log(balanceWA.toString());
            console.log(balanceP.toString());
            console.log(balanceU.toString());
        }

        // await proxy.joinswapPoolAmountOut(
        //     crpPoolAddr,
        //     wAVAXtoken,
        //     hre.ethers.utils.parseEther('1.0'),
        //     hre.ethers.utils.parseEther('1.0'),
        //     { value: hre.ethers.utils.parseEther('1.0') },
        // );

        // await proxy.joinswapPoolAmountOut(
        //     crpPoolAddr,
        //     wAVAXtoken,
        //     hre.ethers.utils.parseEther('1.0'),
        //     balanceWA.div(2),
        // );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            PNGtoken,
            hre.ethers.utils.parseEther('1.0'),
            balanceP.div(2),
            refferal.address,
        );

        await proxy.joinswapPoolAmountOut(
            crpPoolAddr,
            USDCeToken,
            hre.ethers.utils.parseEther('1.0'),
            balanceU.div(2),
            refferal.address,
        );
        const totalAmountSendTriCrypto = (await triCrypto.totalSupply()).sub(supplyTriCrypto);
        const feesToManager = totalAmountSendTriCrypto.mul(
            feesManager,
        ).div(parseEther('1'));
        const feesToRefferal = totalAmountSendTriCrypto.mul(
            feesRefferal,
        ).div(parseEther('1'));

        const balanceTriCrypton = await triCrypto.balanceOf(multisig);
        const balanceTriCryptow = (await triCrypto.balanceOf(wizard.address)).sub(balanceTriCryptoWizard);
        const balanceTriCryptor = (await triCrypto.balanceOf(refferal.address)).sub(balanceTriCryptoRefferal);
        const balanceAn = await signer.getBalance();
        const balanceWAn = await wAVAX.balanceOf(multisig);
        const balancePn = await PNG.balanceOf(multisig);
        const balanceUn = await USDCe.balanceOf(multisig);

        if (verbose) {
            console.log(balanceAn.toString());
            console.log(balanceWAn.toString());
            console.log(balancePn.toString());
            console.log(balanceUn.toString());
        }

        assert.isAtMost(feesToManager.sub(balanceTriCryptow).toNumber(), 10 ** -16);
        assert.isAtMost(feesToRefferal.sub(balanceTriCryptor).toNumber(), 10 ** -16);
        assert.isTrue(balanceTriCrypton.sub(balanceTriCrypto).eq(hre.ethers.utils.parseEther('2.0')), 'Wrong amount');
        // assert.isTrue(balanceA.lt(hre.ethers.utils.parseEther('1.0')), 'Amount of AVAX is more than expected');
        // assert.isTrue(balanceA.gt(balanceAn), 'Amount of AVAX is less than expected');
        // assert.isTrue(balanceWA.gt(balanceWAn), 'Amount of wAVAX is less than expected');
        assert.isTrue(balanceP.gt(balancePn), 'Amount of PNG is less than expected');
        assert.isTrue(balanceU.gt(balanceUn), 'Amount of USD is less than expected');
    });

    it('Join pool with multiple tokens', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const triCrypto = await Token.attach(crpPoolAddr);
        const balanceBefore = await triCrypto.balanceOf(multisig);

        const yyPNG = await Token.attach(yyPNGonPangolin);
        const USDCe = await Token.attach(USDCeToken);
        const KACY = await Token.attach(KACYtoken);

        const balanceP = await yyPNG.balanceOf(multisig);
        const balanceU = await USDCe.balanceOf(multisig);
        const balanceK = await KACY.balanceOf(multisig);

        await proxy.joinPool(
            crpPoolAddr,
            hre.ethers.utils.parseEther('5.0'),
            [
                wAVAXtoken,
                USDCeToken,
                yyPNGonPangolin,
                KACYtoken,
            ],
            [
                hre.ethers.utils.parseEther('2.0'),
                balanceU,
                balanceP,
                balanceK,
            ],
            hre.ethers.constants.AddressZero,
            { value: hre.ethers.utils.parseEther('2.0') },
        );

        const balanceAfter = await triCrypto.balanceOf(multisig);
        assert.isTrue(balanceAfter.gt(balanceBefore));
    });

    it.skip('Spot prices', async () => {
        let f = await proxy.getSpotPrice(corePool, KACYtoken, yyAVAXonAAVE);
        let s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, yyAVAXonAAVE);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, KACYtoken, yyUSDCEonPlatypus);
        s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, yyUSDCEonPlatypus);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, KACYtoken, yyPNGonPangolin);
        s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, yyPNGonPangolin);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, yyAVAXonAAVE, yyUSDCEonPlatypus);
        s = await proxy.getSpotPriceSansFee(corePool, yyAVAXonAAVE, yyUSDCEonPlatypus);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, yyAVAXonAAVE, yyPNGonPangolin);
        s = await proxy.getSpotPriceSansFee(corePool, yyAVAXonAAVE, yyPNGonPangolin);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, yyUSDCEonPlatypus, yyPNGonPangolin);
        s = await proxy.getSpotPriceSansFee(corePool, yyUSDCEonPlatypus, yyPNGonPangolin);
        console.log(f.toString());
        console.log(s.toString());

        //

        f = await proxy.getSpotPrice(corePool, KACYtoken, wAVAXtoken);
        s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, wAVAXtoken);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, KACYtoken, USDCeToken);
        s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, USDCeToken);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, KACYtoken, PNGtoken);
        s = await proxy.getSpotPriceSansFee(corePool, KACYtoken, PNGtoken);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, wAVAXtoken, USDCeToken);
        s = await proxy.getSpotPriceSansFee(corePool, wAVAXtoken, USDCeToken);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, wAVAXtoken, PNGtoken);
        s = await proxy.getSpotPriceSansFee(corePool, wAVAXtoken, PNGtoken);
        console.log(f.toString());
        console.log(s.toString());

        f = await proxy.getSpotPrice(corePool, USDCeToken, PNGtoken);
        s = await proxy.getSpotPriceSansFee(corePool, USDCeToken, PNGtoken);
        console.log(f.toString());
        console.log(s.toString());
    });

    it.skip('swapExactAmountIn', async () => {
        const Token = await hre.ethers.getContractFactory('TToken', signer);
        const PNG = await Token.attach(PNGtoken);
        const balance = await PNG.balanceOf(signer.address);

        const CorePool = await hre.ethers.getContractAt('Pool', corePool, signer);
        const l = await CorePool.getBalance(yyPNGonPangolin);
        const o = await CorePool.getBalance(yyUSDCEonPlatypus);
        const p = await CorePool.getDenormalizedWeight(yyPNGonPangolin);
        const q = await CorePool.getDenormalizedWeight(yyUSDCEonPlatypus);

        console.log(l);
        console.log(o);

        const spotPrice = await CorePool.calcSpotPrice(l, p, o, q, hre.ethers.constants.Zero);
        console.log(spotPrice);

        const a = await proxy.exchangeRate(corePool, PNGtoken);
        const b = await proxy.exchangeRate(corePool, USDCeToken);
        // const m = await proxy.getSpotPrice(corePool, PNGtoken, USDCeToken);
        const n = await proxy.getSpotPriceSansFee(corePool, yyPNGonPangolin, yyUSDCEonPlatypus);
        console.log(a);
        console.log(b);
        // console.log(m);
        console.log(n);
        console.log(n.mul(a).div(b));

        const spotPrice2 = await CorePool.calcSpotPrice(l.mul(a), p, o.mul(b), q, hre.ethers.constants.Zero);
        console.log(spotPrice2);
        const yyPNG = await hre.ethers.getContractAt('YakStrategyV2', yyPNGonPangolin, signer);
        const yyUSDCe = await hre.ethers.getContractAt('YakStrategyV2', yyUSDCEonPlatypus, signer);
        const j = await yyPNG.getSharesForDepositTokens(l);
        const k = await yyUSDCe.getSharesForDepositTokens(o);
        const spotPrice3 = await CorePool.calcSpotPrice(j, p, k, q, hre.ethers.constants.Zero);
        console.log(spotPrice3);

        await proxy.swapExactAmountIn(
            corePool,
            PNGtoken,
            balance.div(10),
            USDCeToken,
            hre.ethers.constants.Zero,
            // hre.ethers.constants.MaxUint256,
            hre.ethers.utils.parseEther('500000000'),
        );

        // yyAVAXonAAVE
        // yyUSDCEonPlatypus
        // yyPNGonPangolin
        // PNGtoken
        // USDCeToken
        // KACYtoken
        // wAVAXtoken
    });
});
