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
VITE_HYPEREVM_WS_URL=
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
- Before approving a browser-local API wallet, the app checks the connected account's active
  Hyperliquid `extraAgents`. If the saved local agent was lost with an old browser/profile, the app
  rotates the named `PricePredict` agent in-place from the connected wallet and continues the order
  flow without requiring users to recover old browser storage or visit Hyperliquid settings.
- HYPE spot order prices, order sizes, and follow-up Core-to-HyperEVM HYPE transfer amounts use the
  Hyperliquid SDK tick/lot-size formatters rather than fixed frontend precision.
- Market state uses a fast UI cadence for active rounds: contract state every 2 seconds, bet events
  every 3 seconds, user bet history every 5 seconds, Hyperliquid mids every 3 seconds, and countdown
  labels re-render locally every second.
- Bet actions are disabled outside the active betting window, show a live `previewBet` quote with
  first-bet price impact included, default to a 1 USDC stake and 10% slippage limit, refresh the
  quote immediately before submission, and decode market custom errors into user-readable messages.
- Bet submission reuses the visible quote for `minSharesOut`, supplies explicit gas limits for
  market writes, and maps RPC rate-limit failures to retry guidance to avoid surfacing raw viem
  contract-call traces to users.
- Contract writes are submitted through the connected EVM wallet.
- Hyperliquid Core recharge actions are shown as explicit action previews before submission.
  Core-to-HyperEVM linked-token transfers use Hyperliquid `sendAsset`, not legacy `spotSend`, so
  they work for unified-account wallets.
- HyperEVM reads can use an optional `VITE_HYPEREVM_WS_URL` when the selected RPC provider exposes
  a WebSocket endpoint. The app falls back to `VITE_HYPEREVM_RPC_URL` HTTP transport, and contract
  state remains the on-chain source of truth.
- Market write actions show a top-right transaction notification immediately after wallet
  submission, update the notification after the HyperEVM receipt succeeds or fails, and then dismiss
  it automatically.
- User bet history shows recent bet amount, round number, settled result, estimated payout, and ROI
  by combining `BetPlaced` logs with `rounds(roundId)` reads. Pending rounds show their current
  round state until settlement.
- Users should review every wallet signature and exchange action, especially HYPE spot purchases
  and Core-to-EVM transfers.
