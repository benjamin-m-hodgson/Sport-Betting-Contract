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
                $('#editLeague').show();
            }
            // TODO replace to check if account is an authorized league host
            if (account == owner) {
                $('#addMatch').show();
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

function commitResult(homeScore, awayScore) {
	var num = randomNum().toString();
	console.log(num);
	var address = "ca35b7d915458ef540ade6068dfe2f44e8fa733c";
	console.log(address);
	var saltString = num + address;
	console.log(saltString);
	var salt = web3.sha3(web3.toHex(saltString), {encoding:"hex"}).substring(2);
	console.log(salt);
	var resultKey = web3.sha3(web3.toHex(salt) + web3.toHex(homeScore) + web3.toHex(awayScore), {encoding:"hex"});
	console.log(resultKey);
	return salt;
}

function revealResult(salt, homeScore, awayScore) {
	var resultKey = web3.sha3(web3.toHex(salt) + web3.toHex(homeScore) + web3.toHex(awayScore), {encoding:"hex"});
	console.log(resultKey);
}

// button click functions

function submitAddLeague() {
    // TODO handle submission
    matchLinkListener();
}

function cancelAddLeague() {
    matchLinkListener();
}

function submitAddResult() {
    // TODO handle submission
    $('#placeResult').hide();
    $('#placeBet').show();
    matchLinkListener();
}

function cancelAddResult() {
    $('#placeResult').hide();
    $('#placeBet').show();
    matchLinkListener();
}

function addResult() {
    $('#matchTable').hide();
    $('#addLeague').hide();
    $('#placeBet').hide();
	document.getElementById("betTitle").textContent="Submit Result";
    $('#placeResult').show();
    $('#betForm').show();
    // TODO take match data from html
}

// Listeners

function matchLinkListener() {
    $('#matchTable').show();
    $('#leagueForm').hide();
    $('#betForm').hide();
    $('#addLeague').hide();
}

function editLeagueListener() {
    $('#addLeague').show();
    // TODO resort match table list to display league information
}

function addLeagueListener() {
    $('#matchTable').hide();
    $('#addLeague').hide();
    $('#leagueForm').show();
    // TODO resort match table list to display league information
}

function matchBetListener() {
    $('#matchTable').hide();
	$('#addLeague').hide();
	$('#placeResult').hide();
	document.getElementById("betTitle").textContent="Place Bet";
	$('#placeBet').show();
    $('#betForm').show();
}

function randomNum() {
	return Math.floor(Math.random() * 10000000000000) + 1
}

window.addEventListener('load', function() {

    // hide/show html
    $('#editLeague').hide();    // hide the edit League link in the header
    $('#addLeague').hide();     // hide the Add League button
    $('#leagueForm').hide();    // hide the form to add a league
    $('#betForm').hide();       // hide the form to place a bet
    $('#addMatch').hide();      // hide the add match link in the header

    // attach listeners
    var matchLink = document.querySelector('#matchLink');
	matchLink.addEventListener('click', function(event) {
        matchLinkListener();
    });

    var editLeagueLink = document.querySelector('#editLeague');
	editLeagueLink.addEventListener('click', function(event) {
        editLeagueListener();
    });

    var addLeagueBtn = document.querySelector('#addLeague');
	addLeagueBtn.addEventListener('click', function(event) {
        addLeagueListener();
    });

    var addMatchLink = document.querySelector('#addMatch');
	addMatchLink.addEventListener('click', function(event) {
        console.log('add match');
    });

    var match = document.querySelector('#match');
	match.addEventListener('click', function(event) {
        matchBetListener();
    });

	// connect to web3
	if (typeof web3 !== 'undefined') {
		web3Provider = web3.currentProvider;
        web3 = new Web3(web3Provider);
        setAccount();
		revealResult(commitResult(1, 1), 1, 1);
	} else {
		console.log('No web3? You should consider trying MetaMask!');
	}

});
