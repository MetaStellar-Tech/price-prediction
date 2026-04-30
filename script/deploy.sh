#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
MODE="${1:-dry-run}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy .env.example to .env and fill the deployment values."
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

RPC_URL="${RPC_URL:-https://rpc.hyperliquid.xyz/evm}"
CHAIN_ID="${CHAIN_ID:-999}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: $name"
    exit 1
  fi
}

require_env DEPLOYER_ADDRESS
require_env DEPLOYER_PRIVATE_KEY
require_env STAKE_TOKEN
require_env ADMIN
require_env OPERATOR
require_env FEE_RECIPIENT
require_env BTC_PERP_INDEX
require_env BTC_SZ_DECIMALS

FORGE_ARGS=(
  script
  "$ROOT_DIR/script/DeployPricePredictionMarket.sol:DeployPricePredictionMarket"
  --sig "run()"
  --rpc-url "$RPC_URL"
)

FORGE_ARGS+=(--chain-id "$CHAIN_ID")

case "$MODE" in
  dry-run)
    ;;
  broadcast|deploy)
    FORGE_ARGS+=(--broadcast)
    ;;
  verify)
    require_env ETHERSCAN_API_KEY
    FORGE_ARGS+=(--broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY")
    ;;
  *)
    echo "Usage: $0 [dry-run|broadcast|deploy|verify]"
    exit 1
    ;;
esac

cd "$ROOT_DIR"
forge "${FORGE_ARGS[@]}"
