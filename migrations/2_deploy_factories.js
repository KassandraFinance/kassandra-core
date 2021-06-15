const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');
const CRPFactory = artifacts.require('CRPFactory');
const ESPFactory = artifacts.require('ESPFactory');
const BFactory = artifacts.require('BFactory');
const KassandraSafeMath = artifacts.require('BalancerSafeMath');
const KassandraSafeMathMock = artifacts.require('BalancerSafeMathMock');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        await deployer.deploy(BFactory);
        await deployer.deploy(KassandraSafeMathMock);
    }

    await deployer.deploy(KassandraSafeMath);
    await deployer.deploy(RightsManager);
    await deployer.deploy(SmartPoolManager);

    deployer.link(KassandraSafeMath, CRPFactory);
    deployer.link(RightsManager, CRPFactory);
    deployer.link(SmartPoolManager, CRPFactory);

    await deployer.deploy(CRPFactory);

    if (network === 'development' || network === 'coverage') {
        deployer.link(KassandraSafeMath, ESPFactory);
        deployer.link(RightsManager, ESPFactory);
        deployer.link(SmartPoolManager, ESPFactory);

        await deployer.deploy(ESPFactory);
    }
};
