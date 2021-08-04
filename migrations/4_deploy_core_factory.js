const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(Factory);
    const factory = await Factory.deployed();
    await factory.setCRPFactory(CRPFactory.address);
};
