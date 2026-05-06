# Implementation Status

Last updated: 2026-05-06

## Completed And Verified

- [x] Foundry project structure added.
- [x] `PricePredictionMarket` implemented with admin, operator, fee recipient, one-active-round state machine.
- [x] ERC20 USDC-style staking flow implemented.
- [x] Bet amount floor implemented: each bet must deliver at least `1 USDC` (`1e6` USDC-style token
  units) to the contract.
- [x] Hyperliquid CoreRead BTC perp oracle price read implemented through the native L1Read precompile address.
- [x] Dynamic share pricing implemented with time premium, trend adjustment, pool imbalance, clamps, and average execution slippage.
- [x] Default pricing parameters dampen first-bet, trend, time, and pool-imbalance price movement to
  reduce ordinary quote-to-submission failures.
- [x] `minSharesOut` protection implemented.
- [x] Settlement implemented for Up win, Down win, and draw.
- [x] No-contest settlement implemented for empty winning-side rounds with full stake refund.
- [x] Push-based batched cleanup implemented.
- [x] Failed cleanup transfers escrow to `pendingPayouts` and can be claimed later.
- [x] Round-sensitive configs, including fee recipient, snapshot at round start.
- [x] Betting close is permissionless after `stopBetTime`; early `stopBet` still reverts.
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
  `0xF124B81dc9744C3E8Fd68886b04A3722628ea2e7`.
- [x] Repo-local operator runner added for `status`, `set-operator`, one-shot `tick`, and
  continuous `loop` maintenance.
- [x] Operator runner sends now use a configurable `OPERATOR_GAS_PRICE`, defaulting to `1gwei`, so
  routine maintenance transactions do not rely on potentially higher RPC fee suggestions.
- [x] Operator runner suppresses Foundry nightly-build warnings by default with
  `FOUNDRY_DISABLE_NIGHTLY_WARNING=true`.
- [x] Repo-local Hyperliquid live market-maker harness added for reusable maker wallets, funding,
  approvals, balanced low-cost betting, post-cleanup rebalancing, and review report generation.
- [x] Live market-maker harness skips near-expiry betting windows, parses `previewBet` shares across
  old and new `cast` output formats, and treats `InvalidState` / `BetWindowClosed` bet reverts as
  stale-window races instead of stopping the loop.
- [x] Live market-maker harness `loop` defaults to `WATCH_MODE=auto`: it uses websocket
  `eth_subscribe` for `BetPlaced` logs only when `WS_RPC_URL` is explicitly set, otherwise it uses
  low-latency `eth_getLogs` polling with `EVENT_POLL_SECONDS=2`; `WATCH_MODE=poll` remains
  available for the older state polling-only mode. Log polling chunks requests at
  `LOG_QUERY_BLOCK_SPAN=50`.
- [x] Vercel-ready pure frontend added under `web/` with landing page, wallet connect, HyperCore /
  HyperEVM account panels, recharge action previews, betting, permissionless settle, pending payout
  claim, and user bet history.
- [x] Frontend defaults configured for HyperEVM mainnet chain id `999`, deployed market
  `0xF124B81dc9744C3E8Fd68886b04A3722628ea2e7`, and stake token
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
- [x] Frontend HYPE top-up flow checks active Hyperliquid `extraAgents` before `approveAgent`,
  reuses the browser-local agent when it is already authorized, and rotates the named
  `PricePredict` agent in-app when the previous browser-local agent was lost.
- [x] Frontend HYPE top-up orders format spot order price, spot order size, and follow-up
  Core-to-EVM HYPE transfer amount with Hyperliquid SDK tick/lot-size helpers instead of
  hard-coding frontend precision.
- [x] Frontend market state refresh cadence tightened: core market reads poll every 2 seconds,
  market bet events every 3 seconds, user bet history every 5 seconds, Hyperliquid mids every 3
  seconds, and visible round countdowns re-render locally every second.
- [x] Frontend bet flow includes market custom errors in the ABI, disables the bet button outside
  the active betting window, and maps `InvalidState`, `BetWindowClosed`, `InvalidAmount`, and
  `SlippageExceeded` failures to user-readable messages.
- [x] Frontend bet ticket shows live Up/Down winning-payout estimates from `previewBet`, includes
  first-bet price impact, hides raw share amounts from the user-facing ticket, and defaults to a 1
  USDC stake with 80% slippage.
- [x] Frontend bet submission reuses the visible quote for `minSharesOut`, supplies explicit gas
  limits for market writes, and maps RPC rate-limit failures to retry guidance instead of showing
  raw viem contract-call traces.
- [x] Frontend market writes show a top-right transaction notification after wallet submission,
  update it when the HyperEVM receipt succeeds or fails, and dismiss it automatically after the
  final state is shown.
- [x] Frontend supports an optional HyperEVM WebSocket RPC URL for wagmi/viem watch reads while
  keeping HTTP RPC as fallback.
- [x] Frontend bet history shows recent bet amount, round number, settled result, estimated payout,
  and ROI by joining user `BetPlaced` logs with `rounds(roundId)` reads.

## Verification

- [x] `forge fmt --check`
- [x] `forge build`
- [x] `forge test -vvv`
- [x] `bash -n ops/operator.sh`
- [x] `bash -n integration/hyperliquid-live-harness/market-maker.sh`
- [x] Embedded market-maker websocket listener JavaScript syntax check with `node --check`
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
  Frontend realtime reads may use a configured HyperEVM WebSocket RPC endpoint, with HTTP RPC kept
  as fallback.
- Deployment remains Foundry-first and uses `.env` plus `script/deploy.sh`; generated `broadcast/`
  artifacts are not committed. The default deployment target is Hyperliquid EVM mainnet.
- Operations remain Foundry/cast based and repo-local. The operator runner is not a production Go
  watcher, risk engine, or off-chain oracle service.
- The live market-maker harness is a rehearsal tool for contract interaction coverage. It is not a
  production market maker, does not seek profit, and keeps generated private keys only in an ignored
  local env file. Harness transaction sends default to async mode with explicit gas settings to
  avoid aborting on transient Hyperliquid RPC receipt-polling block-height errors. The harness also
  avoids submitting bets too close to `stopBetTime`, continues watching if a bet races a round
  state transition, and uses low-latency event-log polling by default because the public
  Hyperliquid EVM RPC does not expose websocket subscriptions. Third-party websocket RPCs remain
  supported by setting `WS_RPC_URL`.
- Simulation tests provide practical adversarial coverage, not a formal proof of no arbitrage.
