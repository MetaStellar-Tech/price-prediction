# Contract Security Baseline

## Non-Negotiable Invariants

- Only `operator` may start rounds.
- Any wallet may stop betting after `stopBetTime`; no wallet may stop betting before `stopBetTime`.
- Only `admin` may update roles and protocol parameters.
- A new round cannot start until the previous round is fully cleaned.
- Bets are accepted only during `Betting`, before `stopBetTime`, and when the actual received stake
  amount is at least `1 USDC` (`1e6` USDC-style token units).
- Settlement is permissionless after `settleTime`.
- Settlement reads final BTC price once and stores the result.
- Fees are charged only from the losing pool.
- Draws refund original stake and charge no fee.
- No-contest rounds refund original stake and charge no fee.
- Cleanup is monotonic by participant index and cannot double-pay processed accounts.
- Failed cleanup transfers are escrowed in `pendingPayouts` instead of blocking the round.

## Funds Model

The contract uses an ERC20 USDC-style stake token. Users transfer stake into the contract during `bet`. The protocol never mints or borrows the stake asset.

The canonical share pricing, settlement, and payout formulas are documented in `docs/protocol/ALGORITHMS.md`.

Non-draw payout:

```text
fee = loserPool * feeBps / 10000
payoutPool = winnerPool + loserPool - fee
userPayout = payoutPool * userWinningShares / totalWinningShares
```

Draw payout:

```text
userPayout = userUpStake + userDownStake
fee = 0
```

No-contest payout:

```text
userPayout = userUpStake + userDownStake
fee = 0
```

Integer rounding can leave residual dust in the contract. V1 does not expose an admin sweep function to avoid weakening payout safety.

## Parameter Bounds

- `feeBps` is capped at `2000`.
- `stopBetOffset` must be lower than `roundDuration`.
- The default timing is a `120 seconds` betting window and a `130 seconds` round duration, leaving a
  `10 seconds` buffer between betting close and settlement.
- Share prices are clamped by configured min and max bps.
- BTC `szDecimals` must be at most `18`.
- Round-sensitive config, including `feeRecipient`, is snapshotted at round start. Admin updates apply to later rounds.

## Known V1 Limits

- `claimPendingPayout` can still fail while the account remains blocked by the stake token.
- Simulation tests are adversarial validation, not a formal no-arbitrage proof.
- `CoreReadAttestor` fallback is documented but not implemented in V1.
