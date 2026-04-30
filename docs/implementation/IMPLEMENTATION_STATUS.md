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

## Verification

- [x] `forge fmt --check`
- [x] `forge build`
- [x] `forge test -vvv`
- [x] `bash -n integration/hyperliquid-live-harness/market-maker.sh`

## Current Boundaries

- V1 uses native HyperEVM L1Read/CoreRead only.
- `CoreReadAttestor` is documented as a future fallback and is not implemented.
- V1 does not include production watcher, Go backend, Hardhat, or main-path TypeScript harness.
- Deployment remains Foundry-first and uses `.env` plus `script/deploy.sh`; generated `broadcast/`
  artifacts are not committed. The default deployment target is Hyperliquid EVM mainnet.
- Operations remain Foundry/cast based and repo-local. The operator runner is not a production Go
  watcher, risk engine, or off-chain oracle service.
- The live market-maker harness is a rehearsal tool for contract interaction coverage. It is not a
  production market maker, does not seek profit, and keeps generated private keys only in an ignored
  local env file. Harness transaction sends default to async mode with explicit gas settings to
  avoid aborting on transient Hyperliquid RPC receipt-polling block-height errors.
- Simulation tests provide practical adversarial coverage, not a formal proof of no arbitrage.
