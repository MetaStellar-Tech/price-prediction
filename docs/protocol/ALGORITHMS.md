# Protocol Algorithms

This document is the canonical V1 description for share pricing, settlement, and payout math.

All share prices use basis points:

```text
10000 bps = 1 stake token unit per share
```

BTC prices are stored internally as `priceE8`.

## Share Pricing Algorithm

Each bet mints accounting shares for one direction:

```text
Direction.Up
Direction.Down
```

The quoted direction price is:

```text
sharePriceBps =
    basePriceBps
  + timePremiumBps
  + trendAdjustmentBps
  + poolImbalanceAdjustmentBps
```

The result is clamped:

```text
sharePriceBps = clamp(sharePriceBps, minSharePriceBps, maxSharePriceBps)
```

Default V1 parameters:

```text
MIN_BET_AMOUNT = 1e6
stopBetOffset = 120 seconds
roundDuration = 130 seconds
basePriceBps = 10000
maxTimePremiumBps = 1500
maxTrendAdjustmentBps = 1500
trendMoveCapBps = 1000
maxPoolImbalanceAdjustmentBps = 1500
minSharePriceBps = 2000
maxSharePriceBps = 20000
```

### Time Premium

Late bets are more expensive because the bettor has more information.

```text
elapsed = min(block.timestamp - round.startTime, roundDuration)
timePremiumBps = maxTimePremiumBps * elapsed / roundDuration
```

The premium applies to both directions.

### Trend Adjustment

The trend component compares the current BTC price with the round base price:

```text
priceMoveBps =
    abs(currentPriceE8 - basePriceE8) * 10000 / basePriceE8

cappedMoveBps = min(priceMoveBps, trendMoveCapBps)

trendMagnitudeBps =
    maxTrendAdjustmentBps * cappedMoveBps / trendMoveCapBps
```

Direction sign:

```text
currentPriceE8 > basePriceE8 and buying Up   => +trendMagnitudeBps
currentPriceE8 > basePriceE8 and buying Down => -trendMagnitudeBps

currentPriceE8 < basePriceE8 and buying Down => +trendMagnitudeBps
currentPriceE8 < basePriceE8 and buying Up   => -trendMagnitudeBps

currentPriceE8 == basePriceE8                => 0
```

Buying with the current trend is more expensive. Buying against the current trend is cheaper.

### Pool Imbalance Adjustment

The pool component makes crowded directions more expensive and cold directions cheaper.

For quoted side `side`:

```text
upPoolAfter = upPool + addedAmount if side is Up else upPool
downPoolAfter = downPool + addedAmount if side is Down else downPool
totalPoolAfter = upPoolAfter + downPoolAfter
```

If `totalPoolAfter == 0`, the adjustment is zero.

Otherwise:

```text
sidePoolShareBps = sidePoolAfter * 10000 / totalPoolAfter
skewBps = sidePoolShareBps - 5000

poolImbalanceAdjustmentBps =
    maxPoolImbalanceAdjustmentBps * skewBps / 5000
```

Examples:

```text
Up pool = 800
Down pool = 200

buying Up:
sidePoolShareBps = 8000
skewBps = +3000
pool adjustment = positive

buying Down:
sidePoolShareBps = 2000
skewBps = -3000
pool adjustment = negative
```

### Average Execution And Slippage

Each bet uses average execution pricing. The contract computes:

```text
received = stakeToken.balanceOf(marketAfterTransfer) - stakeToken.balanceOf(marketBeforeTransfer)
priceBefore = quoteSharePriceBps(roundId, direction, currentPriceE8, 0)
priceAfter = quoteSharePriceBps(roundId, direction, currentPriceE8, received)
averageSharePriceBps = (priceBefore + priceAfter) / 2
```

Minted shares:

```text
shares = received * 10000 / averageSharePriceBps
```

The bettor supplies `minSharesOut`. The bet reverts if:

```text
amount < MIN_BET_AMOUNT
received < MIN_BET_AMOUNT
shares < minSharesOut
```

This protects users from unexpected price movement and prevents a large order from taking all shares at the pre-trade cold-side price.

## Settlement And Payout Algorithm

Settlement is permissionless after `round.settleTime`. It can be called from `Betting` or `BettingClosed`. Calling `settle` from `Betting` after the deadline effectively closes the round and prevents operator withholding.

The contract reads the final BTC price once from Hyperliquid CoreRead and stores it as `finalPriceE8`.

Outcome:

```text
finalPriceE8 > basePriceE8 => Outcome.Up
finalPriceE8 < basePriceE8 => Outcome.Down
finalPriceE8 = basePriceE8 => Outcome.Draw
```

If the price points to a side with no winning shares, the round is a no-contest:

```text
Outcome.Up candidate and upShares == 0     => Outcome.NoContest
Outcome.Down candidate and downShares == 0 => Outcome.NoContest
```

### Non-Draw Settlement

If `Up` wins:

```text
winnerPool = upPool
loserPool = downPool
totalWinningShares = upShares
userWinningShares = user.upShares
```

If `Down` wins:

```text
winnerPool = downPool
loserPool = upPool
totalWinningShares = downShares
userWinningShares = user.downShares
```

Fee is charged only from the losing pool:

```text
fee = loserPool * feeBps / 10000
```

Winner payout pool:

```text
payoutPool = winnerPool + loserPool - fee
```

Each winner receives:

```text
userPayout = payoutPool * userWinningShares / totalWinningShares
```

Losers receive zero in non-draw rounds.

The protocol transfers `fee` to `feeRecipient` after all participant payouts are processed.

### Draw And No-Contest Settlement

A draw occurs when final BTC price equals the base BTC price.

No-contest occurs when the final BTC price points to an empty winning side.

There is no winner, loser, or protocol fee in either case:

```text
fee = 0
```

Each participant receives original stake back:

```text
userPayout = user.upStake + user.downStake
```

Shares do not affect draw refunds.
Shares do not affect no-contest refunds.

### Batched Cleanup

`cleanup(roundId, maxCount)` is permissionless and push-first.

The round stores `cleanupIndex`. Each cleanup call processes:

```text
participants[cleanupIndex ... cleanupIndex + maxCount)
```

Before each participant payout transfer, `cleanupIndex` advances. This makes cleanup monotonic and prevents double payment even if the stake token has callback behavior. Cleanup is also protected by a reentrancy guard.

If a payout transfer fails, the amount is credited to:

```text
pendingPayouts[user]
```

The cleanup batch continues and the user can later call:

```text
claimPendingPayout()
```

When all participants are processed:

```text
feeTransferred = true
state = Cleaned
```

Then the fee is transferred to `feeRecipient` if `fee > 0`. If the fee transfer fails, the amount is credited to `pendingPayouts[feeRecipient]`.

## Round Config Snapshots

The following values are snapshotted when a round starts:

```text
pricingConfig
feeBps
feeRecipient
roundDuration
btcPerpIndex
btcSzDecimals
```

Admin updates affect only future rounds. This prevents a live round from using one oracle or pricing config at start and another at settlement or late betting.

## Rounding

All calculations use integer division. This can leave small residual dust in the contract. V1 intentionally has no admin sweep function because sweeping pooled assets before stronger accounting is specified would weaken payout safety.

## Economic Validation

The test suite includes deterministic pricing tests and a sampled simulation that searches for double-sided lock-profit combinations where one actor buys both `Up` and `Down`.

The simulation is practical adversarial coverage, not a formal proof that no arbitrage exists.
