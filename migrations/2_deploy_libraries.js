const KassandraConstantsMock = artifacts.require('KassandraConstantsMock');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const KassandraSafeMathMock = artifacts.require('KassandraSafeMathMock');
const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');

const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development') {
        await Promise.all([
            deployer.deploy(KassandraConstantsMock),
            deployer.deploy(KassandraSafeMathMock),
        ]);
    }

    await Promise.all([
        deployer.deploy(KassandraSafeMath),
        deployer.deploy(RightsManager),
        deployer.deploy(SmartPoolManager),
    ]);

    await Promise.all([
        deployer.link(KassandraSafeMath, CRPFactory),
        deployer.link(RightsManager, CRPFactory),
        deployer.link(SmartPoolManager, CRPFactory),

        deployer.link(SmartPoolManager, Factory),
    ]);
};
