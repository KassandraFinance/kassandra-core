const CRPFactory = artifacts.require('CRPFactory');

module.exports = async function (deployer) {
    await deployer.deploy(CRPFactory);
};
