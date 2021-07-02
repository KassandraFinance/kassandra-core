const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');
const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');
const KassandraConstantsMock = artifacts.require('KassandraConstantsMock');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        await deployer.deploy(KassandraConstantsMock);
        await deployer.deploy(KassandraSafeMathMock);
    }

    await deployer.deploy(KassandraSafeMath);
    await deployer.deploy(RightsManager);
    await deployer.deploy(SmartPoolManager);

    deployer.link(KassandraSafeMath, CRPFactory);
    deployer.link(RightsManager, CRPFactory);
    deployer.link(SmartPoolManager, CRPFactory);

    const factory = await deployer.deploy(Factory);
    const crpFactory = await deployer.deploy(CRPFactory);
    factory.setFactory(crpFactory.address);
};
