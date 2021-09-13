const KassandraConstantsMock = artifacts.require('KassandraConstantsMock');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');
const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');

const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer, network) {
    if (network === 'development') {
        await Promise.all([
            deployer.deploy(KassandraConstantsMock),
            deployer.deploy(KassandraSafeMathMock),
        ]);
    }

    await deployer.deploy(KassandraSafeMath);
    await deployer.deploy(RightsManager);
    await deployer.deploy(SmartPoolManager);

    await deployer.link(KassandraSafeMath, CRPFactory);
    await deployer.link(RightsManager, CRPFactory);
    await deployer.link(SmartPoolManager, CRPFactory);

    await deployer.link(SmartPoolManager, Factory);
};
