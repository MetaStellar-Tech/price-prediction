# PricePrediction Web

Vercel-ready pure frontend for the deployed PricePrediction market on Hyperliquid EVM mainnet.

## Stack

- Vite + React + TypeScript
- wagmi + viem for HyperEVM wallet reads and contract writes
- TanStack Query for polling HyperEVM and Hyperliquid API state
- No backend, no custodial key path, no private-key input
- Hyperliquid spot orders use a locally generated API wallet after connected-wallet approval

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
- HYPE spot purchases do not ask the connected wallet to sign Hyperliquid L1 order typed data
  directly. The app generates a trading-only Hyperliquid API wallet in browser storage, asks the
  connected wallet to approve that agent, and then signs the L1 order locally with the agent key.
- Contract writes are submitted through the connected EVM wallet.
- Hyperliquid Core recharge actions are shown as explicit action previews before submission.
  Core-to-HyperEVM linked-token transfers use Hyperliquid `sendAsset`, not legacy `spotSend`, so
  they work for unified-account wallets.
- Users should review every wallet signature and exchange action, especially HYPE spot purchases
  and Core-to-EVM transfers.
