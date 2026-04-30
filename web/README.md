# PricePrediction Web

Vercel-ready pure frontend for the deployed PricePrediction market on Hyperliquid EVM mainnet.

## Stack

- Vite + React + TypeScript
- wagmi + viem for HyperEVM wallet reads and contract writes
- TanStack Query for polling HyperEVM and Hyperliquid API state
- No backend, no custodial key path, no private-key input

## Environment

Copy the example file when local overrides are needed:

```sh
cp .env.example .env.local
```

Supported variables:

```text
VITE_HYPEREVM_RPC_URL=https://rpc.hyperliquid.xyz/evm
VITE_HYPERLIQUID_INFO_URL=https://api.hyperliquid.xyz/info
VITE_HYPERLIQUID_EXCHANGE_URL=https://api.hyperliquid.xyz/exchange
VITE_MARKET_ADDRESS=0x406661e7AeF968441d53bc9557be3a8FAa92A67B
VITE_STAKE_TOKEN_ADDRESS=0xb88339CB7199b77E23DB6E890353E22632Ba630f
```

## Commands

```sh
npm install
npm run dev
npm run typecheck
npm run lint
npm run build
```

## Mainnet Assumptions

- HyperEVM chain id is `999`.
- HyperEVM RPC defaults to `https://rpc.hyperliquid.xyz/evm`.
- HYPE is the native gas token.
- `PricePredictionMarket` is deployed at `0x406661e7AeF968441d53bc9557be3a8FAa92A67B`.
- The stake token is `0xb88339CB7199b77E23DB6E890353E22632Ba630f`.

## Safety Notes

- The app never asks for private keys.
- Contract writes are submitted through the connected EVM wallet.
- Hyperliquid Core recharge actions are shown as explicit action previews before submission.
- Users should review every wallet signature and exchange action, especially HYPE spot purchases
  and Core-to-EVM transfers.

