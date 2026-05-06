# Market Maker Live Harness

`integration/hyperliquid-live-harness/market-maker.sh` is a repo-local live rehearsal harness for
the deployed `PricePredictionMarket`. It is not a production watcher, risk engine, or profit-seeking
market maker.

The harness keeps a small set of reusable wallets funded, places conservative two-sided bets after
external users enter a round, and writes post-round review artifacts for contract validation.

## Environment

Create the local secret env once:

```sh
./integration/hyperliquid-live-harness/market-maker.sh init-wallets
```

This writes:

```text
integration/hyperliquid-live-harness/.market-maker.env
```

The file contains one collector wallet and six maker wallets. It is ignored by git and must stay
local. The command refuses to overwrite an existing wallet env.

The default target is the recorded Hyperliquid EVM mainnet deployment:

```text
RPC_URL=https://rpc.hyperliquid.xyz/evm
CHAIN_ID=999
MARKET_ADDRESS=0xF124B81dc9744C3E8Fd68886b04A3722628ea2e7
STAKE_TOKEN=0xb88339CB7199b77E23DB6E890353E22632Ba630f
FOUNDRY_DISABLE_NIGHTLY_WARNING=true
```

The harness loads its local wallet env first, then loads the repo-root `.env`. Shared deployment
values such as `RPC_URL`, `CHAIN_ID`, `MARKET_ADDRESS`, and `STAKE_TOKEN` should be maintained in
the root `.env` so the operator runner, web app defaults, and market-maker harness target the same
contract. `FOUNDRY_DISABLE_NIGHTLY_WARNING` defaults to `true` inside the harness so repeated
Foundry/cast reads do not pollute status and loop output.

After wallet initialization, fund the printed collector address with enough USDC and HYPE for the
rehearsal. The collector funds each maker up to `10 USDC` and `0.02 HYPE`.

## Commands

Show wallet and round state:

```sh
./integration/hyperliquid-live-harness/market-maker.sh status
```

Fund maker wallets from the collector:

```sh
./integration/hyperliquid-live-harness/market-maker.sh fund
```

Approve market USDC spending from maker wallets:

```sh
./integration/hyperliquid-live-harness/market-maker.sh approve
```

Watch active rounds and place balancing maker bets after external participants appear. By default,
`WATCH_MODE=auto` uses low-latency `eth_getLogs` polling for `BetPlaced` events because the public
Hyperliquid EVM RPC does not expose websocket subscriptions:

```sh
./integration/hyperliquid-live-harness/market-maker.sh loop
```

To use a third-party websocket RPC, provide `WS_RPC_URL`:

```sh
WS_RPC_URL=wss://example-rpc.invalid ./integration/hyperliquid-live-harness/market-maker.sh loop
```

To force the older state polling-only watcher:

```sh
WATCH_MODE=poll ./integration/hyperliquid-live-harness/market-maker.sh loop
```

Rebalance maker USDC after the current round is `Cleaned`:

```sh
./integration/hyperliquid-live-harness/market-maker.sh rebalance
```

Write a post-round review report:

```sh
./integration/hyperliquid-live-harness/market-maker.sh review
```

To review a specific historical round:

```sh
./integration/hyperliquid-live-harness/market-maker.sh review 12
```

## Strategy

The harness does not try to predict BTC direction or maximize profit. It tries to keep live
interaction flowing at low cost:

- It only reacts after a non-maker participant appears in the current round.
- In default `WATCH_MODE=auto`, it uses websocket subscriptions only when `WS_RPC_URL` is set.
  Otherwise it scans market `BetPlaced` logs every `EVENT_POLL_SECONDS`, defaulting to `10`, to
  avoid putting avoidable load on the public Hyperliquid EVM RPC endpoint.
- `POLL_SECONDS` remains a heartbeat and fallback state-check interval in auto/log/websocket modes.
  It defaults to `45`. In `WATCH_MODE=poll`, it is the full state polling interval.
- In event-log modes, maker-originated `BetPlaced` events are ignored before any chain state reads.
  Non-maker events drive immediate market-maker evaluation. Full participant reconciliation is only
  performed every `ACTIVITY_RECONCILE_SECONDS`, defaulting to `180`, as a missed-event safety net.
- It prioritizes the empty or smaller pool to reduce no-contest risk.
- It keeps aggregate maker exposure near a `40/60` to `60/40` Up/Down band.
- It caps each maker at `6 USDC` per round and all makers at `24 USDC` per round.
- It uses mostly `1-3 USDC` bets, only allowing larger bets when one side is severely underfunded.
- It calls `previewBet` before `bet` and applies a conservative `minSharesOut`.
- It skips new bets when the chain timestamp is within `MAKER_BET_DEADLINE_BUFFER_SECONDS`
  seconds of `stopBetTime`, defaulting to `8`, so permissionless `stopBet` races do not stop the
  loop.
- It normalizes numeric `cast` reads to plain base-10 integers, so Foundry output that includes
  bracketed scientific notation remains safe for shell arithmetic.
- It treats transient read-side RPC failures such as Hyperliquid public RPC `-32005` rate limits as
  recoverable. Read calls retry with `RPC_TRANSIENT_BACKOFF_SECONDS`, and log polling keeps the
  previous `lastSeen` block until the failed chunk is read successfully.
- If a submitted maker bet still races a state transition and reverts with `InvalidState` or
  `BetWindowClosed`, the harness logs the stale-window result and keeps watching later rounds.

Round progression remains separate. Use `ops/operator.sh loop` or manual operator commands for
`startRound`, `stopBet`, `settle`, and `cleanup`.

## Reports

Reports are written under:

```text
integration/hyperliquid-live-harness/runs/<timestamp>-round-<id>/
```

Each run contains:

- `events.jsonl`: raw market logs for the configured block range.
- `balances-after.txt`: collector and maker balances.
- `round.txt`: round state, pools, shares, fee, cleanup index, and participant count.
- `positions.txt`: participant positions labeled as maker or external.
- `review.md`: validation summary and warnings.

For narrower event scans, pass block bounds as environment variables:

```sh
FROM_BLOCK=33813039 TO_BLOCK=latest ./integration/hyperliquid-live-harness/market-maker.sh review
```

## RPC Send Mode

The harness defaults to async transaction submission with explicit gas values:

```text
CAST_SEND_ASYNC=1
GAS_PRICE_WEI=3100000000
MARKET_GAS_LIMIT=500000
TOKEN_GAS_LIMIT=80000
HYPE_TRANSFER_GAS_LIMIT=21000
WATCH_MODE=auto
POLL_SECONDS=45
EVENT_POLL_SECONDS=10
ACTIVITY_RECONCILE_SECONDS=180
LOG_LOOKBACK_BLOCKS=4
LOG_QUERY_BLOCK_SPAN=50
RPC_TRANSIENT_RETRIES=3
RPC_TRANSIENT_BACKOFF_SECONDS=30
MAKER_BET_DEADLINE_BUFFER_SECONDS=8
WS_RPC_URL=
WS_RECONNECT_SECONDS=3
```

This avoids aborting the workflow when the Hyperliquid RPC accepts a transaction but receipt polling
hits a transient block-height error. Later `status`, `review`, or block explorer checks should be
used to confirm the final state.

The official public Hyperliquid EVM RPC supports HTTP JSON-RPC but not websocket subscriptions. If
`WS_RPC_URL` is empty, `WATCH_MODE=auto` uses short-interval log polling instead of deriving a
websocket URL. If `WS_RPC_URL` is set and the websocket connection closes, the loop reconnects after
`WS_RECONNECT_SECONDS`.

`LOG_QUERY_BLOCK_SPAN` defaults to `50` to stay within the public Hyperliquid EVM RPC
`eth_getLogs` range limit.

`RPC_TRANSIENT_RETRIES` and `RPC_TRANSIENT_BACKOFF_SECONDS` apply only to read-side RPC operations
such as `cast call`, `cast block-number`, `cast block`, `cast balance`, and `cast logs`. The
defaults are intentionally conservative because the public Hyperliquid endpoint rate-limits bursty
polling. Transaction sends are not retried automatically, because a failed receipt or RPC response
may still correspond to a transaction that was accepted by the network.
