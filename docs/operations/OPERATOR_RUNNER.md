# Operator Runner

`ops/operator.sh` is a Foundry/cast based maintenance runner for an already deployed
`PricePredictionMarket`. It is intentionally small and repo-local: it is not a production Go
watcher, risk engine, or off-chain oracle service.

## Environment

The runner reads `.env`.

Required for all runner commands:

```sh
RPC_URL=https://rpc.hyperliquid.xyz/evm
CHAIN_ID=999
MARKET_ADDRESS=0xF124B81dc9744C3E8Fd68886b04A3722628ea2e7
```

Required to set a separate operator:

```sh
ADMIN_PRIVATE_KEY=
OPERATOR_ADDRESS=
```

Required to advance rounds:

```sh
OPERATOR_PRIVATE_KEY=
CLEANUP_BATCH_SIZE=50
OPERATOR_TICK_SECONDS=15
OPERATOR_GAS_PRICE=1gwei
OPERATOR_PRIORITY_GAS_PRICE=
```

`OPERATOR_ADDRESS` can be different from `ADMIN`. The admin only needs to call `set-operator`.
Routine market maintenance should use `OPERATOR_PRIVATE_KEY`.

`OPERATOR_GAS_PRICE` is passed to `cast send --gas-price` for every runner transaction. It defaults
to `1gwei` to keep routine operator maintenance costs low. Increase it if HyperEVM rejects or
delays transactions during a congested period, or set it to an empty value to let `cast` and the RPC
estimate fees automatically. `OPERATOR_PRIORITY_GAS_PRICE` is optional and is only passed when set.

## Commands

Show current market state:

```sh
./ops/operator.sh status
```

Set the on-chain operator:

```sh
./ops/operator.sh set-operator
```

Run one maintenance step:

```sh
./ops/operator.sh tick
```

Run continuously:

```sh
./ops/operator.sh loop
```

## Tick Policy

Each `tick` reads the active round and performs at most one state transition:

- `currentRoundId == 0`: call `startRound`.
- `Betting`: after `stopBetTime`, call `stopBet`.
- `BettingClosed`: after `settleTime`, call `settle`.
- `Settled`: call `cleanup(roundId, CLEANUP_BATCH_SIZE)`.
- `Cleaned`: call `startRound` for the next round.

The runner does not weaken contract permissions. `startRound` still requires the configured
on-chain operator. `stopBet`, `settle`, and `cleanup` are permissionless in the contract after their
respective timing/state gates, but the runner signs them with the operator key for operational
consistency.
