pragma solidity ^0.4.8;

// Utility contract for ownership functionality.
contract owned {
    address public owner;

    constructor() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

/**
 * @author Ben Hodgson
 *
 * Sport Betting Contract
 *
 * Actors:
 *  1. Owner: contract owner, can add or remove match makers
 *  2. Match makers: can create and remove matches and supply match results
 *  3. Betters: can place bets on matches
 *
 * Betters are allowed one bet per match and can place and remove bets anytime
 * before a match is set to begin. If a betters bet was correct, they can
 * withdraw their reward after the match is marked finished by match makers.
 *
 * Match makers can begin to submit results 95 minutes after a match began.
 * Only match makers can submit results. Once resultsNecessary
 * percent of total match makers (currently 75%) have submitted results for the
 * match the match is marked as finished and no more results can be submitted.
 * The final result is considered to be the most submitted result by match makers.
 * Match makers can only claim a reward if their submission matches the final result.
 *
 * By only allowing 75% of match makers to submit a result it creates an incentive
 * for match makers to expediently submit results to guarantee they receive a
 * reward. Match makers can then withdraw rewards for their correct result submissions
 * once a match is marked as finished. The reward for match makers is taken as
 * 1-resultShare (currently 1%) of the total bet pool split evenly.
 * A reward is only issued to match makers if the remaining resultShare (currently 99%)
 * of the bet pool is greater in value than the winning pool to ensure correct
 * betters don't lose money.
 *
 * This incentivization encourages match makers to prioritize submitting results
 * for more popular matches to maximize returns on larger betting pools. However,
 * this platform is suited for betting on large scale matches that draw
 * large audiences. It is reasonable to assume that match makers
 * will only create matches they believe enough people will want to bet on.
 * By this logic all matches posted will have a reasonable number of betters
 * so it is likely the reward for correct results will be large enough to
 * incentivize match makers to supply results for the match.
 */
contract Betting is owned {
    using SafeMath for uint;

    // store the authorized leagues
    mapping (bytes32 => uint) public leagueIndex;
    League[] public leagues;

    // constants that control contract functionality
    uint public resultsNecessary = uint(3).div(uint(4));
    uint public resultShare = uint(99).div(uint(100));

    struct League {
        address host;
        string name;
        // store the matches
        mapping (bytes32 => uint) matchIndex;
        Match[] matches;
        // store the authorized arbiters
        mapping(address => uint) arbiterIndex;
        Arbiter[] arbiters;
    }

    struct Bet {
        bytes32 matchHash;
        address owner;
        string betOnTeam;
        uint amount;
        bool withdrawn;
    }

    struct Team {
        string name;
        uint score;
    }

    struct Match {
        bytes32 hash;
        string homeTeam;
        string awayTeam;
        string league;
        uint startTime;
        bool finished;
        mapping (address => uint) betterIndex;
        Bet[] bets;
        mapping (address => bytes32) resultHash;
        mapping (bytes32 => uint) resultCountIndex;
        Count[] resultCount;
        uint betPool;
    }

    struct Result {
        bytes32 hash;
        bytes32 matchHash;
        Team homeTeam;
        Team awayTeam;
    }

    struct Count {
        bool valid;
        bytes32 value;
        Result matchResult;
    }

    struct Arbiter {
        address id;
    }

    constructor() public {
        addLeague(owner, "Genesis");
    }

    /**
     * Add League
     *
     * Make `makerAddress` a league named `leagueName`
     *
     * @param makerAddress ethereum address to be added as the league host
     * @param leagueName public name for that league
     */
    function addLeague(
        address makerAddress,
        string leagueName
    ) onlyOwner public {
        bytes32 leagueHash = keccak256(abi.encodePacked(leagueName));
        // Check existence of league.
        uint index = leagueIndex[leagueHash];
        if (index == 0) {
            // Add league to ID list.
            leagueIndex[leagueHash] = leagues.length;
            // index gets leagues.length, then leagues.length++
            index = leagues.length++;
        }

        // Create and update storage
        League storage m = leagues[index];
        m.host = makerAddress;
        m.name = leagueName;
    }

    /**
     * Remove a league
     *
     * @notice Remove match maker designation from `makerAddress` address.
     *
     * @param leagueName the name of the league to be removed
     */
    function removeleague(string leagueName) onlyOwner public {
        bytes32 leagueHash = validateLeague(leagueName);

        // Rewrite the match maker storage to move the 'gap' to the end.
        for (uint i = leagueIndex[leagueHash];
                i < leagues.length - 1; i++) {
            leagues[i] = leagues[i+1];
            leagueIndex[keccak256(abi.encodePacked(leagues[i].name))] = i;
        }

        // Delete the last match maker
        delete leagueIndex[leagueHash];
        delete leagues[leagues.length-1];
        leagues.length--;
    }

    /**
     * Add an Arbiter to a specified League
     *
     * Make `arbiterAddress` an arbiter for league `leagueName`
     *
     * @param arbiterAddress ethereum address to be added as a league arbiter
     * @param leagueName public name for that league
     */
    function addLeagueArbiter(
        address arbiterAddress,
        string leagueName
    ) onlyOwner public {
        bytes32 leagueHash = validateLeague(leagueName);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        // Check existence of league arbiter
        uint index = thisLeague.arbiterIndex[arbiterAddress];
        if (index == 0) {
            // Add league arbiter to ID list.
            thisLeague.arbiterIndex[arbiterAddress] = thisLeague.arbiters.length;
            // index gets length, then length++
            index = thisLeague.arbiters.length++;
        }

        // Create and update storage
        Arbiter storage a = thisLeague.arbiters[index];
        a.id = arbiterAddress;
    }

    /**
     * Remove an arbiter from a league
     *
     * @notice Remove arbiter designation from `arbiterAddress` address.
     *
     * @param arbiterAddress ethereum address to be removed as league arbiter
     * @param leagueName the name of the league
     */
    function removeLeagueArbiter(
        address arbiterAddress,
        string leagueName
    ) onlyOwner public {
        bytes32 leagueHash = validateLeagueArbiter(arbiterAddress, leagueName);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        uint index = thisLeague.arbiterIndex[arbiterAddress];

        // Rewrite storage to move the 'gap' to the end.
        for (uint i = index;
                i < thisLeague.arbiters.length - 1; i++) {
            thisLeague.arbiters[i] = thisLeague.arbiters[i+1];
            thisLeague.arbiterIndex[thisLeague.arbiters[i].id] = i;
        }

        // Delete the tail
        delete thisLeague.arbiterIndex[arbiterAddress];
        delete thisLeague.arbiters[thisLeague.arbiters.length-1];
        thisLeague.arbiters.length--;
    }

    /**
     * Allows only match makers to create a match
     *
     * @param homeTeam the home team competing in the match
     * @param awayTeam the away team competing in the match
     * @param league the match pertains to
     * @param startTime the time the match begins
     */
    function createMatch(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) public returns (bytes32 matchHash) {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0, "Invalid league");
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        // require this is the league host
        require(thisLeague.host == msg.sender, "Sender is not the league host");

        matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = thisLeague.matchIndex[matchHash];
        if (index == 0) {
            thisLeague.matchIndex[matchHash] = thisLeague.matches.length;
            index = thisLeague.matches.length++;
        }

        // Create and update storage
        Match storage newMatch = thisLeague.matches[index];
        newMatch.hash = matchHash;
        newMatch.homeTeam = homeTeam;
        newMatch.awayTeam = awayTeam;
        newMatch.league = league;
        newMatch.startTime = startTime;
        newMatch.finished = false;
    }

    /**
     * Allows only match makers to remove a match. Refunds all bets placed
     * on the match.
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function removeMatch(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) public {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0, "Invalid league");
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        // require this is the league host
        require(thisLeague.host == msg.sender, "Sender is not the league host");

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = thisLeague.matchIndex[matchHash];
        require(index != 0 || thisLeague.matches[index].hash == matchHash);
        // require the match hasn't started
        require(now < thisLeague.matches[index].startTime);

        // refund bets
        for (uint b = 0; b < thisLeague.matches[index].bets.length; b++) {
            if (!thisLeague.matches[index].bets[b].withdrawn) {
                Bet storage thisBet = thisLeague.matches[index].bets[b];
                thisBet.withdrawn = true;
                thisBet.owner.transfer(thisBet.amount);
            }
        }

        // Rewrite the matches storage to move the 'gap' to the end.
        for (uint i = thisLeague.matchIndex[matchHash];
                i < thisLeague.matches.length - 1; i++) {
            thisLeague.matches[i] = thisLeague.matches[i + 1];
            thisLeague.matchIndex[thisLeague.matches[i].hash] = i;
        }

        // Delete the last match
        delete thisLeague.matchIndex[matchHash];
        delete thisLeague.matches[thisLeague.matches.length - 1];
        thisLeague.matches.length--;
    }

    /**
     * Returns the match information that bears the hash generated with the user
     * input parameters
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the name of the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function getMatch(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) view public returns(bytes32, string, string, string, uint, bool) {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0, "Invalid league");
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = thisLeague.matchIndex[matchHash];
        require(index != 0 || thisLeague.matches[index].hash == matchHash);
        Match storage retMatch = thisLeague.matches[index];
        return (
            retMatch.hash,
            retMatch.homeTeam,
            retMatch.awayTeam,
            retMatch.league,
            retMatch.startTime,
            retMatch.finished
        );
    }

    /**
     * Allow only match makers to submit a result for a match
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     * @param homeScore the score reported for the homeTeam
     * @param awayScore the score reported for the awayTeam
     */
    function submitMatchResult(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime,
        uint homeScore,
        uint awayScore
    ) public {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0, "Invalid league");
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        // require this is a league arbiter
        require(
            thisLeague.arbiterIndex[msg.sender] != 0 ||
            thisLeague.arbiters[thisLeague.arbiterIndex[msg.sender]].id == msg.sender,
            "Sender is not an appointed league arbiter"
        );

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[matchHash]];
        // make sure match is valid
        require(thisMatch.hash == matchHash, "Invalid match");
        // require match is finished but a result is not finalized
        require(now > startTime + 95 && !thisMatch.finished, "Match is not finished");
        // only allow one result submission per address
        require(thisMatch.resultHash[msg.sender] == 0, "Result already submitted");
        storeMatchResult(msg.sender, league, matchHash, homeTeam, homeScore, awayTeam, awayScore);
    }

    /**
     * Stores the result specified by the function parameters and attributes the
     * submission to the sender address.
     *
     * @param sender the address that submitted this result
     * @param league the league the match to be removed pertains to
     * @param matchHash the unique hash that identifies the match
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param homeScore the score reported for the homeTeam
     * @param awayScore the score reported for the awayTeam
     */
    function storeMatchResult(
        address sender,
        string league,
        bytes32 matchHash,
        string homeTeam,
        uint homeScore,
        string awayTeam,
        uint awayScore
    ) private {
        League storage thisLeague = leagues[leagueIndex[keccak256(abi.encodePacked(league))]];
        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[matchHash]];
        Team memory home = Team(homeTeam, homeScore);
        Team memory away = Team(awayTeam, awayScore);
        // hash the result information
        bytes32 resultKey = keccak256(abi.encodePacked(
            matchHash,
            home.name,
            home.score,
            away.name,
            away.score
        ));
        // map the sender's address to the result hash
        thisMatch.resultHash[sender] = resultKey;
        // map the result hash to an index in the result counter array
        uint countIndex = thisMatch.resultCountIndex[resultKey];
        if (countIndex == 0 && !thisMatch.resultCount[countIndex].valid) {
            // Add result to ID list
            thisMatch.resultCountIndex[resultKey] = thisMatch.resultCount.length;
            countIndex = thisMatch.resultCount.length++;
            // identify the result and mark it valid
            thisMatch.resultCount[countIndex].matchResult = Result(
                resultKey, matchHash, home, away);
            thisMatch.resultCount[countIndex].valid = true;
        }
        // add 1 to the number of people who submitted this result
        Count storage thisCount = thisMatch.resultCount[countIndex];
        thisCount.value = thisCount.value.add(uint(1));
        // check if a sufficient amount of results have been submitted
        processResults(league, matchHash);
    }

    /**
     * Allows only match makers that submitted a correct result for a match
     * withdraw a small reward taken from the bet pool for the match.
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function withdrawResult(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) public {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[matchHash]];
        // require the match is finished
        require(thisMatch.finished);
        bytes32 finalResultHash = findFinalResultHash(homeTeam, awayTeam, league, startTime);
        // require they submitted the correct result
        require(finalResultHash == thisMatch.resultHash[msg.sender]);
        // reset storage to only allow one result withdrawal
        thisMatch.resultHash[msg.sender] = bytes32(0);
        uint countIndex = thisMatch.resultCountIndex[finalResultHash];
        Count storage resultCount = thisMatch.resultCount[countIndex];
        uint winningPool = calculateWinningPool(league, matchHash,
                                    resultCount.matchResult.winningTeam.name);
        uint rewardPool = thisMatch.betPool.mul(resultShare);
        // reward if there are enough losers to guarantee winners don't lose money
        if (rewardPool > winningPool) {
            uint resultPool = thisMatch.betPool.sub(rewardPool);
            uint reward = resultPool.div(resultCount.value);
            msg.sender.transfer(reward);
        }
    }

    /**
     * Allows anyone to place a bet on a match specified by the given
     * function arguments.
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     * @param betOnTeam the team that is bet to win the match
     */
    function placeBet(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime,
        string betOnTeam
    ) payable public {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        // make sure this is a valid bet
        uint index = validateBet(homeTeam, awayTeam, league,
                startTime, betOnTeam);
        Match storage matchBetOn = thisLeague.matches[index];
        uint betIndex = matchBetOn.betterIndex[msg.sender];
        if (betIndex == 0) {
            // Add bet owner to ID list.
            matchBetOn.betterIndex[msg.sender] = matchBetOn.bets.length;
            betIndex = matchBetOn.bets.length++;
        }

        // Create and update storage
        Bet storage b = matchBetOn.bets[betIndex];
        b.matchHash = matchBetOn.hash;
        b.owner = msg.sender;
        b.withdrawn = false;

        // place the bet on the correct team
        if (keccak256(abi.encodePacked(betOnTeam)) ==
                keccak256(abi.encodePacked(matchBetOn.homeTeam))) {
            b.betOnTeam = homeTeam;
        }
        else {
            b.betOnTeam = awayTeam;
        }
        b.amount = msg.value;
        matchBetOn.betPool = matchBetOn.betPool.add(msg.value);
    }

    /**
     * Allows anyone to remove a bet they placed on a match
     *
     * @notice msg.sender must have a bet placed on the match
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function removeBet(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) payable public {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // make sure match is a valid match
        uint index = thisLeague.matchIndex[matchHash];
        require(index != 0 || thisLeague.matches[index].hash == matchHash);
        // require the user has placed a bet on the match
        uint betIndex = thisLeague.matches[index].betterIndex[msg.sender];
        require(betIndex != 0 || thisLeague.matches[index].bets[betIndex].owner == msg.sender);
        // require the match hasn't started
        require(now < thisLeague.matches[index].startTime);

        // save the bet amount for refunding purposes
        uint betAmount = thisLeague.matches[index].bets[betIndex].amount;
        uint expectedBalance = address(this).balance.sub(betAmount);

        // Rewrite the bets storage to move the 'gap' to the end.
        Bet[] storage addressBets = thisLeague.matches[index].bets;
        for (uint i = betIndex; i < addressBets.length - 1; i++) {
            addressBets[i] = addressBets[i+1];
            thisLeague.matches[index].betterIndex[addressBets[i].owner] = i;
        }

        // Delete the last bet
        delete thisLeague.matches[index].betterIndex[msg.sender];
        delete addressBets[addressBets.length-1];
        addressBets.length--;

        // refund and update match bet pool
        thisLeague.matches[index].betPool = thisLeague.matches[index].betPool.sub(betAmount);
        msg.sender.transfer(betAmount);
        assert(address(this).balance == expectedBalance);
    }

    /**
     * Allows anyone to retrieve the information about a bet they placed on
     * a specified match. Information returned includes the match hash for the
     * match the bet was placed on, the bet owner's address, the team bet on,
     * the amount bet, and whether the bet has been withdrawn.
     *
     * @notice msg.sender must have a bet placed on the match
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function getBet(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) view public returns (bytes32, address, string, uint, bool) {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // require the bet is on a valid match
        uint index = thisLeague.matchIndex[matchHash];
        require(index != 0 || thisLeague.matches[index].hash == matchHash);
        // require the user has placed a bet on the match
        uint betIndex = thisLeague.matches[index].betterIndex[msg.sender];
        require(betIndex != 0 || thisLeague.matches[index].bets[betIndex].owner == msg.sender);
        // require this is the bet owner
        Bet storage userBet = thisLeague.matches[index].bets[betIndex];
        require(msg.sender == userBet.owner);
        return (
            matchHash,
            userBet.owner,
            userBet.betOnTeam,
            userBet.amount,
            userBet.withdrawn
        );
    }

    /**
     * Allows anyone to withdraw a bet. If the bet was correct, a reward is
     * calculated and transferred to the account of the msg.sender.
     *
     * @notice msg.sender must have a bet placed on the match
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function withdrawBet(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) public {
        // require it's a valid league
        require(leagueIndex[keccak256(abi.encodePacked(league))] != 0);
        League storage thisLeague = leagues[leagueIndex[keccak256(abi.encodePacked(league))]];

        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // require the match is finished
        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[matchHash]];
        require(thisMatch.finished);
        // require the bet hasn't been withdrawn and msg.sender owns a bet
        uint betIndex = thisMatch.betterIndex[msg.sender];
        Bet storage userBet = thisMatch.bets[betIndex];
        require(!userBet.withdrawn && userBet.owner == msg.sender);

        bytes32 finalResultHash = findFinalResultHash(homeTeam, awayTeam, league, startTime);
        uint resultIndex = thisMatch.resultCountIndex[finalResultHash];
        Result storage finalResult = thisMatch.resultCount[resultIndex].matchResult;
        // withdraw Bet
        userBet.withdrawn = true;
        // check if they won the Bet
        if (keccak256(abi.encodePacked(userBet.betOnTeam))
                == keccak256(abi.encodePacked(finalResult.winningTeam.name))) {
            uint winningPool = calculateWinningPool(league, matchHash,
                                            finalResult.winningTeam.name);
            uint rewardPool = thisMatch.betPool.mul(resultShare);
            // if no losers, return bets
            if (rewardPool <= winningPool) {
                msg.sender.transfer(userBet.amount);
            }
            // otherwise calculate rewards
            else {
                uint reward = rewardPool.mul(userBet.amount.div(winningPool));
                msg.sender.transfer(reward);
            }
        }
    }

    /**
     * Allows anyone to get the final result information for the specified
     * match
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function getFinalResult(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) view public returns (bytes32, bytes32, string, uint, string, uint) {
        // require it's a valid league
        require(leagueIndex[keccak256(abi.encodePacked(league))] != 0);
        League storage thisLeague = leagues[leagueIndex[keccak256(abi.encodePacked(league))]];

        // require the match is finished
        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[getMatchHash(homeTeam, awayTeam, league, startTime)]];
        require(thisMatch.finished);
        // loop through result counter and determine most numerous result
        uint maxCounter = 0;
        Result storage maxResult = thisMatch.resultCount[0].matchResult;
        for (uint i = 0; i < thisMatch.resultCount.length; i++) {
            if (thisMatch.resultCount[i].value > maxCounter) {
                maxCounter = thisMatch.resultCount[i].value;
                maxResult = thisMatch.resultCount[i].matchResult;
            }
        }
        return (
            maxResult.hash,
            maxResult.matchHash,
            maxResult.winningTeam.name,
            maxResult.winningTeam.score,
            maxResult.losingTeam.name,
            maxResult.losingTeam.score
        );
    }

    /**
     * Verifies that 'leagueName' is a valid league
     */
    function validateLeague(string leagueName) view private returns (bytes32) {
        bytes32 leagueHash = keccak256(abi.encodePacked(leagueName));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0, "Invalid league");
        return leagueHash;
    }

    /**
     * Verifies that 'arbiterAddress' is a valid arbiter
     *
     * @notice Also verifies that 'leagueName' is a valid league
     */
    function validateLeagueArbiter(
        address arbiterAddress,
        string leagueName
    ) view private returns (bytes32) {
        bytes32 leagueHash = validateLeague(leagueName);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        uint index = thisLeague.arbiterIndex[arbiterAddress];
        require(thisLeague.arbiters[index].id == arbiterAddress, "Invalid league arbiter");
        return leagueHash;
    }

    /**
     * Returns the hash of the final result for the specified match
     */
    function findFinalResultHash(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) view private returns (bytes32) {
        (bytes32 resultHash,
         bytes32 matchHash,
         string memory winningTeam,
         uint winningScore,
         string memory losingTeam,
         uint losingScore) = getFinalResult(homeTeam, awayTeam, league, startTime);
        return resultHash;
    }

    /**
     * Validates that a bet can be placed on a valid match
     *
     * @return index the match index for the match the bet is placed on
     */
    function validateBet(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime,
        string betOnTeam
    ) view private returns (uint index) {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        index = thisLeague.matchIndex[matchHash];
        // require the match can be bet on
        require((index != 0 || thisLeague.matches[index].hash == matchHash)
            && now < thisLeague.matches[index].startTime);
        // require the bet is on a valid team
        require(keccak256(abi.encodePacked(betOnTeam)) ==
                    keccak256(abi.encodePacked(thisLeague.matches[index].homeTeam))
                || keccak256(abi.encodePacked(betOnTeam)) ==
                    keccak256(abi.encodePacked(thisLeague.matches[index].awayTeam)));
    }

    /**
     * Calculates and returns the sum of the correct bet amounts
     *
     * @param matchHash the hash of the match the bets are for
     * @param league the league the match pertains to
     * @param winningTeam the team that won the match
     */
    function calculateWinningPool(
        string league,
        bytes32 matchHash,
        string winningTeam
    ) view private returns (uint winningPool) {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        Match storage thisMatch = thisLeague.matches[thisLeague.matchIndex[matchHash]];
        winningPool = 0;
        for (uint i = 0; i < thisMatch.bets.length; i++) {
            Bet storage thisBet = thisMatch.bets[i];
            if (keccak256(abi.encodePacked(thisBet.betOnTeam))
                    == keccak256(abi.encodePacked(winningTeam))) {
                winningPool = winningPool.add(thisBet.amount);
            }
        }
    }

    /**
     * Loops through the submitted results to check to see if a sufficient
     * amount of results have been submitted to determine a probable outcome
     *
     * @param league the league the match to be processed pertains to
     * @param matchHash the hash of the match the result is for
     */
    function processResults(string league, bytes32 matchHash) private {
        bytes32 leagueHash = keccak256(abi.encodePacked(league));
        // require it's a valid league
        require(leagueIndex[leagueHash] != 0);
        League storage thisLeague = leagues[leagueIndex[leagueHash]];

        uint index = thisLeague.matchIndex[matchHash];
        Match storage thisMatch = thisLeague.matches[index];
        uint resultSubmissions = 0;
        for (uint i = 0; i < thisMatch.resultCount.length; i++) {
            Count storage thisCount = thisMatch.resultCount[i];
            resultSubmissions = resultSubmissions.add(thisCount.value);
        }
        uint resultRatio = resultSubmissions.div(leagues.length);
        if (resultRatio >= resultsNecessary) {
            thisMatch.finished = true;
        }
    }

    /**
     * Calculates the unique byte32 identifier hash for the specified match
     */
    function getMatchHash(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) pure private returns (bytes32 matchHash){
        matchHash = keccak256(abi.encodePacked(
            homeTeam,
            awayTeam,
            league,
            startTime
        ));
    }

    // fallback payable function
    function() payable public {

    }

    // getter that returns the contract ether balance
    function getEtherBalance() onlyOwner view public returns (uint) {
        return address(this).balance;
    }

    // delete the contract from the blockchain
    function kill() onlyOwner public{
        selfdestruct(owner);
    }

}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

}
