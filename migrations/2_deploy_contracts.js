var Contract = artifacts.require("../contracts/bettingContract");

module.exports = function(deployer) {
  deployer.deploy(Contract);
};
