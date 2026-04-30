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
MARKET_ADDRESS=0x406661e7AeF968441d53bc9557be3a8FAa92A67B
STAKE_TOKEN=0xb88339CB7199b77E23DB6E890353E22632Ba630f
```

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

Watch active rounds and place balancing maker bets after external participants appear. By default
this uses a websocket `eth_subscribe` log stream for `BetPlaced` events and reacts as soon as the
RPC publishes the log:

```sh
./integration/hyperliquid-live-harness/market-maker.sh loop
```

To force the older polling-only watcher:

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
- In default `WATCH_MODE=websocket`, it subscribes to market `BetPlaced` logs over `WS_RPC_URL`
  and runs the maker check immediately when a bet log arrives.
- `POLL_SECONDS` remains a heartbeat and fallback state-check interval in websocket mode. In
  `WATCH_MODE=poll`, it is the full polling interval.
- It prioritizes the empty or smaller pool to reduce no-contest risk.
- It keeps aggregate maker exposure near a `40/60` to `60/40` Up/Down band.
- It caps each maker at `6 USDC` per round and all makers at `24 USDC` per round.
- It uses mostly `1-3 USDC` bets, only allowing larger bets when one side is severely underfunded.
- It calls `previewBet` before `bet` and applies a conservative `minSharesOut`.
- It skips new bets when the chain timestamp is within `MAKER_BET_DEADLINE_BUFFER_SECONDS`
  seconds of `stopBetTime`, defaulting to `8`, so operator-driven `stopBet` races do not stop the
  loop.
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
MAKER_BET_DEADLINE_BUFFER_SECONDS=8
WATCH_MODE=websocket
WS_RPC_URL=
WS_RECONNECT_SECONDS=3
```

This avoids aborting the workflow when the Hyperliquid RPC accepts a transaction but receipt polling
hits a transient block-height error. Later `status`, `review`, or block explorer checks should be
used to confirm the final state.

If `WS_RPC_URL` is empty, the harness derives it from `RPC_URL` by replacing `https://` with
`wss://` or `http://` with `ws://`. If the websocket connection closes, the loop reconnects after
`WS_RECONNECT_SECONDS`.
