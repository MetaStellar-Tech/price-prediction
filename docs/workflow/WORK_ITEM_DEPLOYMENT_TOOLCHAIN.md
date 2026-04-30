# Work Item: Foundry Deployment Toolchain

## Scope

Build a one-command Foundry deployment path for `PricePredictionMarket` that defaults to
Hyperliquid EVM mainnet and reads wallet, private key, protocol roles, stake token, and
Hyperliquid CoreRead constructor parameters from `.env`.

## In Scope

- `.env.example` with required deployment variables.
- Hyperliquid EVM mainnet default RPC and chain id.
- Foundry script entrypoint with deployer key/address validation.
- Shell wrapper for dry-run, broadcast, and optional verification modes.
- Deployment documentation.
- Implementation status update after verification.

## Out Of Scope

- Hardhat deployment flow.
- Go backend, watcher, or production orchestration.
- TypeScript RPC harness.
- Changing protocol funds, settlement, or permission semantics.
