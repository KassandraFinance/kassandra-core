const KassandraConstantsMock = artifacts.require('KassandraConstantsMock');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');
const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        await deployer.deploy(KassandraConstantsMock);
        await deployer.deploy(KassandraSafeMathMock);
    }

    await deployer.deploy(KassandraSafeMath);
    await deployer.deploy(RightsManager);
    await deployer.deploy(SmartPoolManager);
};
