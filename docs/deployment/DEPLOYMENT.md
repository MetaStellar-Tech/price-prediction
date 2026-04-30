# Deployment

PricePrediction uses a Foundry-first deployment flow. The default target is Hyperliquid EVM
mainnet, with chain id `999` and RPC URL `https://rpc.hyperliquid.xyz/evm`. The deployment wallet
and constructor parameters are read from `.env`; real secrets must never be committed.

## Environment

Copy the example file:

```sh
cp .env.example .env
```

Fill these required values:

```sh
RPC_URL=https://rpc.hyperliquid.xyz/evm
CHAIN_ID=999
DEPLOYER_ADDRESS=
DEPLOYER_PRIVATE_KEY=
STAKE_TOKEN=
ADMIN=
OPERATOR=
FEE_RECIPIENT=
BTC_PERP_INDEX=0
BTC_SZ_DECIMALS=5
```

`DEPLOYER_ADDRESS` must match `DEPLOYER_PRIVATE_KEY`. The deploy script checks this before
broadcasting. The deployer pays gas, while `ADMIN`, `OPERATOR`, and `FEE_RECIPIENT` define the
protocol roles stored in the deployed `PricePredictionMarket`.

`RPC_URL` and `CHAIN_ID` default to Hyperliquid EVM mainnet if omitted. To deploy to another
network, override both values explicitly in `.env`.

## Commands

Dry-run against the configured RPC:

```sh
./script/deploy.sh
```

Broadcast a deployment transaction:

```sh
./script/deploy.sh deploy
```

Broadcast and request explorer verification when the target explorer supports the standard
Foundry verifier flow:

```sh
ETHERSCAN_API_KEY=... ./script/deploy.sh verify
```

Foundry writes transaction artifacts under `broadcast/`, which is ignored by git.

Successful production deployments are recorded in `docs/deployment/DEPLOYMENTS.md`.

## Constructor

The deployed contract is:

```solidity
PricePredictionMarket(
    IERC20 stakeToken,
    address admin,
    address operator,
    address feeRecipient,
    uint32 btcPerpIndex,
    uint8 btcSzDecimals
)
```

`btcPerpIndex` and `btcSzDecimals` are network-specific Hyperliquid CoreRead assumptions. Update
them only with values validated for the target HyperEVM deployment.
