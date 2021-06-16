const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');
const CRPFactory = artifacts.require('CRPFactory');
const ESPFactory = artifacts.require('ESPFactory');
const Factory = artifacts.require('Factory');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        await deployer.deploy(KassandraSafeMathMock);
    }

    await deployer.deploy(KassandraSafeMath);
    await deployer.deploy(RightsManager);
    await deployer.deploy(SmartPoolManager);

    deployer.link(KassandraSafeMath, CRPFactory);
    deployer.link(RightsManager, CRPFactory);
    deployer.link(SmartPoolManager, CRPFactory);

    await deployer.deploy(Factory);
    await deployer.deploy(CRPFactory);

    if (network === 'development' || network === 'coverage') {
        deployer.link(KassandraSafeMath, ESPFactory);
        deployer.link(RightsManager, ESPFactory);
        deployer.link(SmartPoolManager, ESPFactory);

        await deployer.deploy(ESPFactory);
    }
};
