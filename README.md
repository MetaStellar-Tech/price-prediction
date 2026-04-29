# PricePrediction

PricePrediction is a pure Solidity / Foundry protocol repository for a token-price-driven prediction market on Hyperliquid HyperEVM.

HyperEVM is the betting and settlement truth layer. HyperCore is the oracle price source. The V1 protocol reads BTC perp oracle prices through Hyperliquid native CoreRead / L1Read precompiles and settles each round on-chain.

## V1 Protocol

- One active prediction round at a time.
- Operator starts a round, stops betting, and settles.
- Users bet an ERC20 USDC-style stake token on `Up` or `Down`.
- The contract mints accounting shares using dynamic odds pricing.
- Winners receive pro-rata payouts by winning shares.
- Protocol fee is charged only from the losing pool.
- Draw rounds refund original stake and charge no fee.
- No-winner rounds are no-contest rounds and refund original stake.
- Anyone can settle after the deadline and call batched `cleanup`.

## Pricing

Share price is expressed in basis points where `10000` means `1 stake token unit per share`.

```text
sharePriceBps =
    basePriceBps
  + timePremiumBps
  + trendAdjustmentBps
  + poolImbalanceAdjustmentBps
```

Each bet executes at the average of the pre-bet and post-bet price:

```text
averageSharePriceBps = (priceBefore + priceAfter) / 2
shares = amount * 10000 / averageSharePriceBps
```

This makes late betting, trend-following, and crowded-side betting more expensive while adding slippage for large orders.

The complete canonical algorithm is documented in `docs/protocol/ALGORITHMS.md`.

## Settlement

Settlement reads the final BTC price from HyperCore through CoreRead. `Up` wins when final price is greater than the round base price, `Down` wins when it is lower, and an exact tie is a draw. If the winning side has no shares, the round is no-contest and all original stake is refunded.

Non-draw rounds charge the protocol fee only from the losing pool. Winners split the winner pool plus the loser pool after fee by winning-share ownership. Draw rounds refund original stake and charge no fee.

The complete payout formula is documented in `docs/protocol/ALGORITHMS.md`.

## Hyperliquid CoreRead

V1 reads BTC price from the Hyperliquid perp oracle price L1Read precompile at:

```text
0x0000000000000000000000000000000000000807
```

The constructor stores:

- `btcPerpIndex`: network-specific BTC perp asset index.
- `btcSzDecimals`: HyperCore size decimals used to normalize the raw oracle price.

The current fallback boundary remains documented as `CoreReadAttestor`, but V1 does not implement off-chain attestor submission.

CoreRead, fee recipient, fee, timing, and pricing parameters are snapshotted when a round starts. Admin updates apply to the next round.

## Verification

```sh
forge fmt --check
forge build
forge test -vvv
```

This repository intentionally does not include a Go backend, production watcher, Hardhat workflow, or TypeScript protocol harness in the main path.
