# Sport-Betting-Contract

A decentralized application that interfaces with a Solidity smart contract on the Ethereum network to enable sport betting. The contract uses a trustless result acquisition system enforced by an implicit Schelling point to reach a consensus match outcome.

## Background

The goal of this project is simple: to enable a platform where select leagues can post matches that any network participant can place a bet on. Match results are determined in a decentralized way. Specified league arbiters are responsible for submitting a vote for the result outcome and the most numerous result submitted is considered the true result. Arbiters that submit this true result can withdraw a reward. Individuals can withdraw their bets and collect rewards once enough arbiters submit results to reach a consensus. More detail about how each step in this system works and the role of each actor is provided in the sections below.

## Leagues

Only the contract owner has the ability to add and remove leagues. This gives the owner discretion over who can create matches and helps ensure that there aren't multiple leagues posting identical matches. Each league is identified by a hash generated from it's unique name:

`bytes32 leagueHash = keccak256(abi.encodePacked(leagueName));`

In practice there might be a league that corresponds to the NBA, another to the NFL, and another to the MLB. All of these leagues post their own unique matches and have their own arbiters that are knowledgeable about the league's matches and can, in theory, be trusted to submit objective results.

#### League Host

The contract owner designates an Ethereum address to act as the league host when a league is added. The league host has the exclusive authority to post matches for that league. A match can only be removed by the league host before the declared start time. When a match is removed all bets placed on it are refunded back to the betters.

#### League Arbiters

The contract owner also has the authority to appoint Ethereum addresses to act as league arbiters. This gives them the right to submit results for matches in their league. Arbiters are rewarded for submitting correct results. It's essential that the owner have the power to add and remove league arbiters rather than the league host so that there is no conflict of interest. One could imagine a corrupt league host adding a large number of addresses they control as arbiters and then creating fraudulent matches. Now the league host can wait for unknowing individuals to place bets, submit false results, and collect rewards on nonexistent matches.

## Matches

Matches can be posted in a league by the league host. Each match is uniquely identified by a hash generated from it's pertinent information:

```
bytes32 matchHash = keccak256(abi.encodePacked(
	            homeTeam,
	            awayTeam,
	            league,
	            startTime
	        ));
```

Logically there is no way more than one match between the same two teams in the same league can start at the same time. This makes this hash positively unique for each match posted.

Matches within the contract logic progress through phases in the following order:

 1. **Posted:** League host posts a match. Individuals can place bets.
 2. **Started:** Match has started. Individuals can no longer bet on the match.
 3. **Ended:** Match has ended and arbiters can start submitting results
 4. **Finalized:** Match result has been finalized. Individuals can collect their bet winnings and arbiters can collect rewards.

#### Match Posted

A match is posted when a league host add's a new match. Each match has a designated start time. Individuals can place bets at any point up until the match starts:

```
require(now < thisMatch.startTime, "Match already started");
```

The league host can also remove a match up until the match starts. Any bets placed are automatically refunded.

#### Match Started

A match has started if the current time is past the match's start time.

```
bool started = now >= thisMatch.startTime;
```

Network participants can no longer place bets and the league host can no longer remove the match.

#### Match Finished

A match is arbitrarily declared finished 95 minutes after it's start time.

```
bool finished = now > thisMatch.startTime + 95 minutes;
```

The result is still unknown, but at this point league arbiters can begin submitting results. If in reality the match isn't concluded 95 minutes after the start time then it's reasonable to assume most arbiters will wait before submitting their result. Arbiters that submit results early, after the match is deemed finished by the contract but not in reality, will likely end up wasting ether on transaction gas costs and receive no reward. More about the incentive for arbiters to submit correct results will be explained later.

#### Match Finalized

A match is considered finalized when enough arbiters have submitted results. The number of arbiters required to constitute "enough" is **72%** of the league's total number of arbiters. More on how this number was derived will be explained later. Once the match is finalized, arbiters that submitted the correct result and network participants that won their bet can begin to collect their rewards.

## Result Acquisition

The result acquisition system is decentralized and structured to reward arbiters for submitting correct results, but how can the contract reliably determine the correct result? The answer lies in game theory. A Schelling point, or focal point, describes the outcome individuals will focus on in the absence of collusion. In this specific case, the Schelling point is the true match result that exists in reality. This is enforced by deeming the most numerous result submission as the correct result. Since the true outcome is the focal point, we can reason that the majority of arbiters will submit this result. Arbiters that don't will lose ether in transaction gas costs and have little chance of receiving a reward.

To examine any weaknesses in this system, let's examine a situation in which an arbiter might try to cheat the system and submit a fraudulent result. Suppose an arbiter, added as a league arbiter by the contract owner, places a large bet on the away team in a match posted by the league host. Now they aim to submit a result that shows an away team victory to win their bet. Let's say the home team won the match in reality, so the arbiter must lie about the match outcome. Logically, the arbiter submits a result showing the away team won. However, the most numerous result submission is considered the true result and other arbiters are motivated to submit this result to collect a reward. This means there must be more fake results than true results. Let's assume that many other arbiters also want to show an away team win to collect rewards on bets they placed on the match. Even if 51% of the arbiters are lying to show the away team won, they would still all need to submit the same fraudulent result to outnumber the remaining, honest arbiters. Without collusion this seems extremely unlikely. To get around this the dishonest arbiter would need to control a majority of the league's arbiters to influence the result with certainty, but since the contract owner has the exclusive power to add arbiters this could be easily thwarted. For example, the contract owner could have a system in place, off the blockchain, to register arbiters and limit one Ethereum address per person or household.

Even if the system above can discourage fraudulent result submission there is still the problem of knowledge asymmetry. If arbiters that submit results later have access to the current result distribution they could be swayed to submit an incorrect result. For example, suppose the last arbiter to submit a result sees that two results have an equal number of submissions. Now they know they can submit either result and are guaranteed a reward, there is no incentive for them to submit the real result. To prevent this the contract employs the **Commit-Reveal** voting scheme. This scheme divides the result submission process into three parts:

 1. **Commit:** Arbiter commits a result as a unique hash.
 2. **Reveal:** Arbiter reveals their result by providing the information used to generate the commit hash. Contract verifies the revealed result matches the committed result.
 3. **Withdraw:** Arbiter's that submitted the correct result can withdraw a reward.

Let's examine each of these steps in more details.

#### Result Commit

A result commit is in the form of a hash unique to the arbiter. The arbiter first generates a result hash from the following information off chain. It's important this hash is calculated off chain and then passed to the contract to avoid showing the actual result in the transaction blocks.

```javascript
bytes32 result = keccak256(abi.encodePacked(
			salt,
			homeScore,
			awayScore
		));
```

The _salt_ in the above hash function is itself a hash and is what ensures the result is unique to the individual arbiter. It's generated off chain as well from the hash of a randomly generated number, _rand_, and the Ethereum address of the arbiter:

```javascript
bytes32 salt = keccak256(abi.encodePacked(rand, address));
```

The random number helps ensure that no one else can generate the arbiter's salt hash and thereby determine the result committed. Only the salt needs to be remembered, or temporarily stored off chain, for the reveal stage. The random number can be completely forgotten at this point.

Once the arbiter submits the _result_, this is hashed together in the contract with the match hash to make the stored result unique to both the arbiter and the match. The result of this hash is stored and attributed to the arbiter.

```
bytes32 storeResult = keccak256(abi.encodePacked(
				result,
				matchHash
			));
```

At what point should the arbiters be allowed to reveal their result? Ideally all of the arbiters should commit a result before the reveal phase begins to increase the sample size and make it more difficult for one individual to control a majority of the league's arbiter addresses, but this is unrealistic. It's possible that every arbiter didn't watch a particular match in real time, or at all, which means there could be a long wait for every arbiter to commit a result. To get around this the commit phase continues until **80%** of the league's arbiters commit results. Afterwards the reveal step begins and the remaining 20% of arbiters are ineligible to claim rewards. This gives two primary benefits: it realistically assumes that some arbiters might not commit a result and simultaneously encourages arbiters to submit results early to claim a reward by creating competition.  

Expediency is a crucial part of this system. Betting becomes much less attractive as the delay to collect rewards grows. With this in mind, arbiters will need to also stake **10 wei** to commit a match result. This stake is refunded when the arbiter reveals their commit. The aim of this stake is to increase the incentive for arbiters to reveal their result and decrease the wait for the finalized match result. For instance, suppose a malevolent arbiter committed an incorrect result. The reveal step has started and nearly all of the arbiters have revealed their results but it's clear that the arbiter won't receive any reward because their result is incorrect. At this point, the arbiter has no incentive to reveal their result at all. The stake combats this problem and provides an incentive for all arbiters to reveal their result.

#### Result Reveal

The reveal step begins once 80% of league arbiters commit a result. The arbiter resubmits their result and supplies the stored _salt_ used for their commit:

```
bytes32 result = keccak256(abi.encodePacked(
			salt,
			homeScore,
			awayScore
		));
```

Unlike in the commit phase, this result hash is generated on chain because at this point it doesn't matter if other arbiters can see the submission. This result is then hashed with the match hash, as it is in the commit phase, and then the contract verifies this matches the stored result from the commit phase.

```
bytes32 storeResult = keccak256(abi.encodePacked(
				result,
				matchHash
			));
bool verified = (storeResult == commitResult)
```

The arbiter is refunded the ether they staked during the commit if _verified_ evaluates to true and the revealed result is the same as the committed result. At this point the arbiter can't reveal their result again, but they are allowed to repeatedly reveal their result until their submission matches their commit.

How many reveals should be required before the match is finalized? Recall, 80% of arbiters must commit results for the reveal phase to begin. It's unrealistic to think that all of the arbiters that commit results will reveal their result, despite the lost stake and reward forfeiture. For instance, if an arbiter loses the _salt_ hash used to commit their result they will be unable to reveal their result. While this possibility could be extremely diminished by storing the _salt_ off chain, it would be difficult to eliminate the chance entirely. To combat this the contract requires **90%** of arbiters that committed results reveal their result to finalize the match. This mathematically means that **72%** of the total league arbiters determine the match outcome and are eligible to receive rewards for submitting the correct result.  The 10% of arbiters that reveal results after the result is finalized still are refunded their stake amount, but are ineligible to receive rewards for their result submission.



## Future Improvements

1. Finish the web application front end that helps users interact with the contracts.
