const TMath = artifacts.require('TMath');
const Token = artifacts.require('Token');
const Factory = artifacts.require('Factory');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        deployer.deploy(TMath);
    }
    deployer.deploy(Factory);
};
