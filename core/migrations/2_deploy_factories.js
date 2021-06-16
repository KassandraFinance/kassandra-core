const Token = artifacts.require('Token');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer, network, accounts) {
    deployer.deploy(Factory);
};
