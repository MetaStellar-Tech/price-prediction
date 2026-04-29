# Hyperliquid Integration Constraints

## Deployment Target

PricePrediction V1 targets Hyperliquid HyperEVM. HyperCore is the BTC oracle source.

## CoreRead Boundary

The protocol reads the BTC perp oracle price through HyperEVM native L1Read / CoreRead precompile:

```text
0x0000000000000000000000000000000000000807
```

The call data is the 32-byte perp asset index. The returned raw price is normalized with Hyperliquid perp size decimals:

```text
price = rawPrice / 10^(6 - szDecimals)
priceE8 = price * 1e8
```

The contract stores `btcPerpIndex` and `btcSzDecimals` as admin-configurable values because asset indices and metadata can differ by network or deployment assumptions.

## Fallback Policy

The repository policy is:

```text
L1Read(primary) + CoreReadAttestor(fallback)
```

V1 implements the L1Read primary path only. A future fallback must be separately specified, tested, and documented before use.

## Out Of Scope

- Production Go watcher or risk engine.
- Main-path TypeScript RPC harness.
- Hardhat workflow.
- Real testnet or mainnet rehearsal outside `integration/hyperliquid-live-harness/`.
