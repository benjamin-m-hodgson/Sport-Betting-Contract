var owner = "0xd566ac2b97ad457202eb4cc31a7b10cb48dfd6d3";
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
            // TODO get owner address from contract
            if (account == owner) {
                $('#addLeague').show();
            }

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

// button click functions

function submitAddLeague() {
    // TODO handle submission
    matchLinkListener();
}

function cancelAddLeague() {
    matchLinkListener();
}

// Listeners

function matchLinkListener() {
    $('#matchTable').show();
    $('#leagueForm').hide();
    $('#betForm').hide();
}

function addLeagueListener() {
    $('#matchTable').hide();
    $('#leagueForm').show();
    $('#betForm').hide();
}


window.addEventListener('load', function() {

    // hide/show html
    $('#addLeague').hide();     // hide the Add League link in the header
    $('#leagueForm').hide();    // hide the form to add a league
    $('#betForm').show();
    $('#matchTable').hide();

    // attach listeners
    var matchLink = document.querySelector('#matchLink');
	matchLink.addEventListener('click', function(event) {
        matchLinkListener();
    });

    var addLeagueLink = document.querySelector('#addLeague');
	addLeagueLink.addEventListener('click', function(event) {
        addLeagueListener();
    });

	// connect to web3
	if (typeof web3 !== 'undefined') {
		web3Provider = web3.currentProvider;
        web3 = new Web3(web3Provider);
        setAccount();
	} else {
		console.log('No web3? You should consider trying MetaMask!');
	}
});
