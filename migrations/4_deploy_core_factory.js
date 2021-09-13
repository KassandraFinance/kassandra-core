const CRPFactory = artifacts.require('CRPFactory');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer) {
    await deployer.deploy(Factory);
    const factory = await Factory.deployed();
    const crpFactory = await CRPFactory.deployed();
    await factory.setCRPFactory(crpFactory.address);
};
