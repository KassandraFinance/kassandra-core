const CRPFactory = artifacts.require('CRPFactory');
const KassandraSafeMath = artifacts.require('KassandraSafeMath');
const RightsManager = artifacts.require('RightsManager');
const SmartPoolManager = artifacts.require('SmartPoolManager');

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(CRPFactory);
};
