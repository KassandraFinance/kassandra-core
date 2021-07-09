const CRPFactory = artifacts.require('CRPFactory');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');

module.exports = async function (deployer, network, accounts) {
    deployer.link(KassandraSafeMath, CRPFactory);
    deployer.link(RightsManager, CRPFactory);
    deployer.link(SmartPoolManager, CRPFactory);

    await deployer.deploy(CRPFactory);
};
