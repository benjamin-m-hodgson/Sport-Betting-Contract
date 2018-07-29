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
    // store the match makers
    mapping (address => uint) public matchMakerIndex;
    MatchMaker[] public matchMakers;
    // store the matches
    mapping (bytes32 => uint) public matchIndex;
    Match[] public matches;
    // constants that control contract functionality
    uint public resultsNecessary = uint(3).div(uint(4));
    uint public resultShare = uint(99).div(uint(100));

    struct MatchMaker {
        address id;
        string name;
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
        Team winningTeam;
        Team losingTeam;
        bool tie;
    }

    struct Count {
        bool valid;
        uint value;
        Result matchResult;
    }

    // Modifier that allows only shareholders to create matches
    modifier onlyMatchMakers {
        require(matchMakerIndex[msg.sender] != 0 || msg.sender == owner);
        _;
    }

    constructor() public {
        addMatchMaker(owner, "Ben");
    }

    /**
     * Add matchMaker
     *
     * Make `makerAddress` a match maker named `makerName`
     *
     * @param makerAddress ethereum address to be added
     * @param makerName public name for that match maker
     */
    function addMatchMaker(
        address makerAddress,
        string makerName
    ) onlyOwner public {
        // Check existence of matchMaker.
        uint index = matchMakerIndex[makerAddress];
        if (index == 0) {
            // Add matchMaker to ID list.
            matchMakerIndex[makerAddress] = matchMakers.length;
            // index gets matchMakers.length, then matchMakers.length++
            index = matchMakers.length++;
        }

        // Create and update storage
        MatchMaker storage m = matchMakers[index];
        m.id = makerAddress;
        m.name = makerName;
    }

    /**
     * Remove match maker
     *
     * @notice Remove match maker designation from `makerAddress` address.
     *
     * @param makerAddress ethereum address to be removed
     */
    function removeMatchMaker(address makerAddress) onlyOwner public {
        require(matchMakerIndex[makerAddress] != 0);

        // Rewrite the match maker storage to move the 'gap' to the end.
        for (uint i = matchMakerIndex[makerAddress];
                i < matchMakers.length - 1; i++) {
            matchMakers[i] = matchMakers[i+1];
            matchMakerIndex[matchMakers[i].id] = i;
        }

        // Delete the last match maker
        delete matchMakerIndex[makerAddress];
        delete matchMakers[matchMakers.length-1];
        matchMakers.length--;
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
    ) onlyMatchMakers public returns (bytes32 matchHash) {
        matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = matchIndex[matchHash];
        if (index == 0) {
            matchIndex[matchHash] = matches.length;
            index = matches.length++;
        }

        // Create and update storage
        Match storage newMatch = matches[index];
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
    ) onlyMatchMakers public {
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = matchIndex[matchHash];
        require(index != 0 || matches[index].hash == matchHash);
        // require the match hasn't started
        require(now < matches[index].startTime);

        // refund bets
        for (uint b = 0; b < matches[index].bets.length; b++) {
            if (!matches[index].bets[b].withdrawn) {
                Bet storage thisBet = matches[index].bets[b];
                thisBet.withdrawn = true;
                thisBet.owner.transfer(thisBet.amount);
            }
        }

        // Rewrite the matches storage to move the 'gap' to the end.
        for (uint i = matchIndex[matchHash];
                i < matches.length - 1; i++) {
            matches[i] = matches[i+1];
            matchIndex[matches[i].hash] = i;
        }

        // Delete the last match
        delete matchIndex[matchHash];
        delete matches[matches.length-1];
        matches.length--;
    }

    /**
     * Returns the match information that bears the hash generated with the user
     * input parameters
     *
     * @param homeTeam the home team competing in the match to be removed
     * @param awayTeam the away team competing in the match to be removed
     * @param league the league the match to be removed pertains to
     * @param startTime the time the match to be removed begins
     */
    function getMatch(
        string homeTeam,
        string awayTeam,
        string league,
        uint startTime
    ) view public returns(bytes32, string, string, string, uint, bool) {
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        uint index = matchIndex[matchHash];
        require(index != 0 || matches[index].hash == matchHash);
        Match storage retMatch = matches[index];
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
    ) onlyMatchMakers public {
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        Match storage thisMatch = matches[matchIndex[matchHash]];
        // make sure match is valid
        require(thisMatch.hash == matchHash);
        // require match is finished but a result is not finalized
        require(now > startTime + 95 && !thisMatch.finished);
        // only allow one result submission per address
        require(thisMatch.resultHash[msg.sender] == 0);
        // Determine winning and losing teams
        Team memory winningTeam = Team("", 0);
        Team memory losingTeam = Team("", 0);
        bool tie = false;
        if (homeScore >= awayScore) {
            winningTeam = Team(homeTeam, homeScore);
            losingTeam = Team(awayTeam, awayScore);
            if (homeScore == awayScore) {
                tie = true;
            }
        }
        else {
            winningTeam = Team(awayTeam, awayScore);
            losingTeam = Team(homeTeam, homeScore);
        }
        // hash the result information
        bytes32 resultKey = keccak256(abi.encodePacked(
            matchHash,
            winningTeam.name,
            winningTeam.score,
            losingTeam.name,
            losingTeam.score,
            tie
        ));
        // map the sender's address to the result hash
        thisMatch.resultHash[msg.sender] = resultKey;
        // map the result hash to an index in the result counter array
        uint countIndex = thisMatch.resultCountIndex[resultKey];
        if (countIndex == 0 && !thisMatch.resultCount[countIndex].valid) {
            // Add result to ID list
            thisMatch.resultCountIndex[resultKey] = thisMatch.resultCount.length;
            countIndex = thisMatch.resultCount.length++;
            // identify the result and mark it valid
            thisMatch.resultCount[countIndex].matchResult = Result(
                resultKey, matchHash, winningTeam, losingTeam, tie);
            thisMatch.resultCount[countIndex].valid = true;
        }
        // add 1 to the number of people who submitted this result
        Count storage thisCount = thisMatch.resultCount[countIndex];
        thisCount.value = thisCount.value.add(uint(1));
        // check if a sufficient amount of results have been submitted
        processResults(matchHash);
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
    ) onlyMatchMakers public {
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        Match storage thisMatch = matches[matchIndex[matchHash]];
        // require the match is finished
        require(thisMatch.finished);
        bytes32 finalResultHash = findFinalResultHash(homeTeam, awayTeam, league, startTime);
        // require they submitted the correct result
        require(finalResultHash == thisMatch.resultHash[msg.sender]);
        // reset storage to only allow one result withdrawal
        thisMatch.resultHash[msg.sender] = bytes32(0);
        uint countIndex = thisMatch.resultCountIndex[finalResultHash];
        Count storage resultCount = thisMatch.resultCount[countIndex];
        uint winningPool = calculateWinningPool(matchHash,
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
        // make sure this is a valid bet
        uint index = validateBet(homeTeam, awayTeam, league,
                startTime, betOnTeam);
        Match storage matchBetOn = matches[index];
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
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // make sure match is a valid match
        uint index = matchIndex[matchHash];
        require(index != 0 || matches[index].hash == matchHash);
        // require the user has placed a bet on the match
        uint betIndex = matches[index].betterIndex[msg.sender];
        require(betIndex != 0 || matches[index].bets[betIndex].owner == msg.sender);
        // require the match hasn't started
        require(now < matches[index].startTime);

        // save the bet amount for refunding purposes
        uint betAmount = matches[index].bets[betIndex].amount;
        uint expectedBalance = address(this).balance.sub(betAmount);

        // Rewrite the bets storage to move the 'gap' to the end.
        Bet[] storage addressBets = matches[index].bets;
        for (uint i = betIndex; i < addressBets.length - 1; i++) {
            addressBets[i] = addressBets[i+1];
            matches[index].betterIndex[addressBets[i].owner] = i;
        }

        // Delete the last bet
        delete matches[index].betterIndex[msg.sender];
        delete addressBets[addressBets.length-1];
        addressBets.length--;

        // refund and update match bet pool
        matches[index].betPool = matches[index].betPool.sub(betAmount);
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
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // require the bet is on a valid match
        uint index = matchIndex[matchHash];
        require(index != 0 || matches[index].hash == matchHash);
        // require the user has placed a bet on the match
        uint betIndex = matches[index].betterIndex[msg.sender];
        require(betIndex != 0 || matches[index].bets[betIndex].owner == msg.sender);
        // require this is the bet owner
        Bet storage userBet = matches[index].bets[betIndex];
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
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // require the match is finished
        Match storage thisMatch = matches[matchIndex[matchHash]];
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
            uint winningPool = calculateWinningPool(matchHash,
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
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        // require the match is finished
        Match storage thisMatch = matches[matchIndex[matchHash]];
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
    ) view private returns (uint index){
        bytes32 matchHash = getMatchHash(homeTeam, awayTeam, league, startTime);
        index = matchIndex[matchHash];
        // require the match can be bet on
        require((index != 0 || matches[index].hash == matchHash)
            && now < matches[index].startTime);
        // require the bet is on a valid team
        require(keccak256(abi.encodePacked(betOnTeam)) ==
                    keccak256(abi.encodePacked(matches[index].homeTeam))
                || keccak256(abi.encodePacked(betOnTeam)) ==
                    keccak256(abi.encodePacked(matches[index].awayTeam)));
    }

    /**
     * Calculates and returns the sum of the correct bet amounts
     *
     * @param matchHash the the hash of the match the bets are for
     * @param winningTeam the team that won the match
     */
    function calculateWinningPool(
        bytes32 matchHash,
        string winningTeam
    ) view private returns (uint winningPool) {
        Match storage thisMatch = matches[matchIndex[matchHash]];
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
     * @param matchHash the hash of the match the result is for
     */
    function processResults(bytes32 matchHash) private {
        uint index = matchIndex[matchHash];
        Match storage thisMatch = matches[index];
        uint resultSubmissions = 0;
        for (uint i = 0; i < thisMatch.resultCount.length; i++) {
            Count storage thisCount = thisMatch.resultCount[i];
            resultSubmissions = resultSubmissions.add(thisCount.value);
        }
        uint resultRatio = resultSubmissions.div(matchMakers.length);
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
