# PricePrediction

PricePrediction is a Solidity / Foundry protocol repository for token-price-driven prediction markets on EVM chains. The project started in the Hyperliquid ecosystem and is being expanded into a multi-chain protocol with Hyperliquid and Arc as priority deployment environments.

## Overview

PricePrediction is a source-available, multi-chain EVM prediction market protocol. It lets users bet on whether a token price will move up or down during a fixed round, settles the result on-chain, and supports price-oracle inputs from HyperCore and other on-chain oracle adapters. The repository focuses on protocol contracts, Foundry tests, deployment and operation scripts, live chain rehearsal harnesses, and a small Vercel-ready frontend in `web/`.

The current V1 implementation is optimized for Hyperliquid HyperEVM, where HyperEVM is the betting and settlement truth layer and HyperCore is the oracle price source. The next deployment track is Arc, an EVM-compatible, stablecoin-native Layer 1 designed for financial applications with USDC-denominated gas, predictable fees, and deterministic finality. This makes Arc a strong fit for prediction markets that need transparent settlement, stable transaction costs, and institutional grade payment and liquidity rails.

The protocol direction is intentionally chain-flexible:

- Hyperliquid-first: use HyperEVM for settlement and HyperCore/CoreRead for low-latency market prices.
- Arc-first expansion: deploy the same Solidity / Foundry protocol surface on Arc and connect price settlement to Arc-compatible oracle sources.
- Multi-oracle architecture: support HyperCore, established on-chain price feeds, and future chain-specific oracle adapters without changing the core prediction-market state machine.
- Stablecoin-native markets: keep USDC-style collateral, deterministic settlement, and predictable user-facing costs as first-class design goals across supported EVM chains.

The explicit repository exception is `web/`, a Vercel-ready pure frontend for real users to connect wallets, inspect HyperCore and HyperEVM account state, recharge, bet, settle, and view history. The protocol path remains Foundry-first; `src/`, `test/`, `script/`, and `ops/` do not depend on the frontend.

## V1 Protocol

- One active prediction round at a time.
- Operator starts a round. Anyone can stop betting after the betting deadline and settle after the settlement deadline.
- Users bet an ERC20 USDC-style stake token on `Up` or `Down`.
- Each bet must deliver at least `1 USDC` worth of stake token units to the contract.
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

This makes late betting, trend-following, and crowded-side betting more expensive while adding bounded slippage for large orders. V1 defaults are intentionally dampened so ordinary quote-to-submission drift is less likely to revert user bets.

The complete canonical algorithm is documented in `docs/protocol/ALGORITHMS.md`.

## Settlement

Settlement reads the final BTC price from HyperCore through CoreRead. `Up` wins when final price is greater than the round base price, `Down` wins when it is lower, and an exact tie is a draw. If the winning side has no shares, the round is no-contest and all original stake is refunded.

Non-draw rounds charge the protocol fee only from the losing pool. Winners split the winner pool plus the loser pool after fee by winning-share ownership. Draw rounds refund original stake and charge no fee.

The complete payout formula is documented in `docs/protocol/ALGORITHMS.md`.

## Oracle And Chain Adapters

PricePrediction separates the prediction-market state machine from the price source used at settlement. The first production adapter reads HyperCore prices through Hyperliquid CoreRead. Future EVM deployments, including Arc, can use chain-native or widely adopted on-chain oracle feeds while preserving the same betting, settlement, payout, and cleanup semantics.

## Hyperliquid CoreRead

V1 reads BTC price from the Hyperliquid perp oracle price L1Read precompile at:

```text
0x0000000000000000000000000000000000000807
```

The constructor stores:

- `btcPerpIndex`: network-specific BTC perp asset index.
- `btcSzDecimals`: HyperCore size decimals used to normalize the raw oracle price.

The current fallback boundary remains documented as `CoreReadAttestor`, but V1 does not implement off-chain attestor submission.

CoreRead, fee recipient, fee, timing, and pricing parameters are snapshotted when a round starts. The default betting window is `120 seconds`, followed by a `10 seconds` settlement buffer. Admin updates apply to the next round.

## Verification

```sh
forge fmt --check
forge build
forge test -vvv
```

## Deployment

The Foundry deployment toolchain currently defaults to Hyperliquid EVM mainnet (`CHAIN_ID=999`, `RPC_URL=https://rpc.hyperliquid.xyz/evm`) and reads wallet, private key, role addresses, stake token, and Hyperliquid CoreRead constructor parameters from `.env`. Arc is the next priority EVM deployment target; Arc-specific deployment parameters and oracle adapter wiring will live in the same Foundry-first workflow as they are added.

```sh
cp .env.example .env
./script/deploy.sh          # dry-run
./script/deploy.sh deploy   # broadcast
```

See `docs/deployment/DEPLOYMENT.md` for the full environment contract and verification mode.

## Operations

The repo includes a small Foundry/cast based operator runner for maintaining an already deployed market. It can set a separate operator, then periodically call `startRound`, `stopBet`, `settle`, and `cleanup` according to the on-chain round state.

```sh
./ops/operator.sh status
./ops/operator.sh set-operator
./ops/operator.sh tick
./ops/operator.sh loop
```

See `docs/operations/OPERATOR_RUNNER.md` for the required `.env` values and tick policy.

The repo also includes an isolated live market-maker harness under `integration/hyperliquid-live-harness/`. It creates reusable local maker wallets, keeps them lightly funded, places low-cost balancing bets after external activity, and writes post-round validation reports. See `docs/operations/MARKET_MAKER_HARNESS.md`.

This repository intentionally does not include a Go backend, production watcher, Hardhat workflow, or TypeScript protocol harness in the main path.

## Web App

The frontend lives in `web/` and targets the deployed HyperEVM mainnet market by default:

```sh
cd web
npm install
npm run dev
npm run build
```

See `web/README.md` for Vercel environment variables, supported network assumptions, and wallet signature safety notes.

## License

This project is source-available under the Business Source License 1.1 (`BUSL-1.1`). Production use, including commercial operation of this protocol or a modified version, requires a separate commercial license from MetaStellar-Tech unless and until the Change License applies. See `LICENSE` for the full terms, including the Change Date and Change License.
