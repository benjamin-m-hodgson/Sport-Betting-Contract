var account;
var web3Provider;
var balanceETH = 0;

//sets account and ethereum balance of that account
function setAccount() {
	//make sure using rinkeby
	web3.version.getNetwork(function(err, netId) {
		if (netId == 4) {
			//set the account display
			account = web3.eth.accounts[0];
			$("#metamaskButton").text(account);

			// set the ethereum balance display
			web3.eth.getBalance(account, function(err, res) {
			balanceETH = Number(web3.fromWei(res, 'ether'));
			$('#balanceETH').text(balanceETH + " ETH");
			$('#balanceETH').show();
			});
		} else {
			$('#metamaskButton').text('Please switch to Rinkeby');
		}
	});
}

window.addEventListener('load', function() {

	// connect to web3
	if (typeof web3 !== 'undefined') {
		web3Provider = web3.currentProvider;
        web3 = new Web3(web3Provider);
        setAccount();
	} else {
		console.log('No web3? You should consider trying MetaMask!');
	}
});
