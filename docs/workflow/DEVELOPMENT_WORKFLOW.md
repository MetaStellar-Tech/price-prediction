# Development Workflow

This repository is Foundry-first and Solidity-only.

## Start

1. Read `AGENTS.md`, `README.md`, and this workflow.
2. For funds, settlement, permissions, or upgrades, also read `docs/security/CONTRACT_SECURITY_BASELINE.md`.
3. For Hyperliquid integration changes, also read `docs/hyperliquid/INTEGRATION_CONSTRAINTS.md`.
4. Check `git status --short --branch` and recent commits.
5. Advance one work item at a time.

## Implementation Order

1. Freeze protocol semantics in docs.
2. Define errors, events, enums, interfaces, and libraries.
3. Implement minimal contract skeleton and role checks.
4. Implement accounting, pricing, settlement, and cleanup.
5. Add Hyperliquid integration boundaries.
6. Add tests and update implementation status.

## Required Checks

```sh
forge fmt --check
forge build
forge test -vvv
```

Use `forge coverage`, Slither, or Echidna when available for broader security work.
