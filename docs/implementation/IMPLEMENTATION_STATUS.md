# Implementation Status

Last updated: 2026-04-30

## Completed And Verified

- [x] Foundry project structure added.
- [x] `PricePredictionMarket` implemented with admin, operator, fee recipient, one-active-round state machine.
- [x] ERC20 USDC-style staking flow implemented.
- [x] Hyperliquid CoreRead BTC perp oracle price read implemented through the native L1Read precompile address.
- [x] Dynamic share pricing implemented with time premium, trend adjustment, pool imbalance, clamps, and average execution slippage.
- [x] `minSharesOut` protection implemented.
- [x] Settlement implemented for Up win, Down win, and draw.
- [x] No-contest settlement implemented for empty winning-side rounds with full stake refund.
- [x] Push-based batched cleanup implemented.
- [x] Failed cleanup transfers escrow to `pendingPayouts` and can be claimed later.
- [x] Round-sensitive configs, including fee recipient, snapshot at round start.
- [x] Settlement is permissionless after deadline.
- [x] Deterministic unit tests implemented.
- [x] Simulation test implemented to search sampled two-sided lock-profit combinations.
- [x] Canonical protocol algorithm documentation added for share pricing, settlement, and payout math.
- [x] Foundry deployment script implemented with `.env` wallet/private-key loading and deployer address validation.
- [x] One-command deployment wrapper implemented for dry-run, broadcast, and optional verifier modes.
- [x] Deployment environment template and deployment documentation added.
- [x] Deployment defaults set to Hyperliquid EVM mainnet (`CHAIN_ID=999`, `RPC_URL=https://rpc.hyperliquid.xyz/evm`).
- [x] Foundry bytecode metadata hash disabled to keep HyperEVM mainnet deployment gas below the
  current block gas limit.
- [x] `PricePredictionMarket` deployed and post-deploy checked on Hyperliquid EVM mainnet at
  `0x406661e7AeF968441d53bc9557be3a8FAa92A67B`.
- [x] Repo-local operator runner added for `status`, `set-operator`, one-shot `tick`, and
  continuous `loop` maintenance.
- [x] Repo-local Hyperliquid live market-maker harness added for reusable maker wallets, funding,
  approvals, balanced low-cost betting, post-cleanup rebalancing, and review report generation.
- [x] Vercel-ready pure frontend added under `web/` with landing page, wallet connect, HyperCore /
  HyperEVM account panels, recharge action previews, betting, permissionless settle, pending payout
  claim, and user bet history.
- [x] Frontend defaults configured for HyperEVM mainnet chain id `999`, deployed market
  `0x406661e7AeF968441d53bc9557be3a8FAa92A67B`, and stake token
  `0xb88339CB7199b77E23DB6E890353E22632Ba630f`.
- [x] Frontend HYPE top-up flow avoids MetaMask `chainId` mismatch on Hyperliquid L1 orders by
  approving a browser-local Hyperliquid API wallet with a Hyperliquid-valid 16-character-or-shorter
  agent name, then signing the spot order with that local agent wallet.
- [x] Frontend Hyperliquid Core signed actions (`approveAgent`, `spotSend`) use an ethers-style
  wallet adapter that signs typed data with the provider's current `eth_chainId` through
  `eth_signTypedData_v4`, avoiding the SDK's viem branch and MetaMask SDK active-chain/domain-chain
  mismatches.
- [x] Frontend Core-to-HyperEVM linked-token transfers use Hyperliquid `sendAsset` instead of
  legacy `spotSend`, so USDC/HYPE recharge supports wallets with `unifiedAccount` enabled.

## Verification

- [x] `forge fmt --check`
- [x] `forge build`
- [x] `forge test -vvv`
- [x] `bash -n integration/hyperliquid-live-harness/market-maker.sh`
- [x] `web`: `npm run typecheck`
- [x] `web`: `npm run lint`
- [x] `web`: `npm run build`

## Current Boundaries

- V1 uses native HyperEVM L1Read/CoreRead only.
- `CoreReadAttestor` is documented as a future fallback and is not implemented.
- V1 does not include production watcher, Go backend, Hardhat, or main-path TypeScript protocol
  harness.
- `web/` is the explicit user-facing frontend exception. It is a pure frontend app for Vercel and
  does not introduce a backend, private-key custody, or protocol harness into the Foundry path.
- Deployment remains Foundry-first and uses `.env` plus `script/deploy.sh`; generated `broadcast/`
  artifacts are not committed. The default deployment target is Hyperliquid EVM mainnet.
- Operations remain Foundry/cast based and repo-local. The operator runner is not a production Go
  watcher, risk engine, or off-chain oracle service.
- The live market-maker harness is a rehearsal tool for contract interaction coverage. It is not a
  production market maker, does not seek profit, and keeps generated private keys only in an ignored
  local env file. Harness transaction sends default to async mode with explicit gas settings to
  avoid aborting on transient Hyperliquid RPC receipt-polling block-height errors.
- Simulation tests provide practical adversarial coverage, not a formal proof of no arbitrage.
