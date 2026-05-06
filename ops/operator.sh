#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
ACTION="${1:-status}"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  echo "Copy .env.example to .env and fill the operator values."
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

RPC_URL="${RPC_URL:-https://rpc.hyperliquid.xyz/evm}"
CHAIN_ID="${CHAIN_ID:-999}"
CLEANUP_BATCH_SIZE="${CLEANUP_BATCH_SIZE:-50}"
OPERATOR_TICK_SECONDS="${OPERATOR_TICK_SECONDS:-30}"
OPERATOR_RPC_TRANSIENT_RETRIES="${OPERATOR_RPC_TRANSIENT_RETRIES:-3}"
OPERATOR_RPC_TRANSIENT_BACKOFF_SECONDS="${OPERATOR_RPC_TRANSIENT_BACKOFF_SECONDS:-30}"
OPERATOR_GAS_PRICE="${OPERATOR_GAS_PRICE-1gwei}"
FOUNDRY_DISABLE_NIGHTLY_WARNING="${FOUNDRY_DISABLE_NIGHTLY_WARNING:-true}"
export FOUNDRY_DISABLE_NIGHTLY_WARNING

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: $name"
    exit 1
  fi
}

first_uint() {
  awk 'match($0, /[0-9]+/) { print substr($0, RSTART, RLENGTH); exit }'
}

is_uint() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_transient_rpc_error() {
  printf '%s' "$1" | grep -Eiq 'rate limited|-32005|too many requests|429|max retries exceeded|temporarily unavailable|timeout|timed out'
}

rpc_read() {
  local attempt=1 output status
  while true; do
    if output="$("$@" 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    else
      status=$?
    fi
    if is_transient_rpc_error "$output" && [ "$attempt" -lt "$OPERATOR_RPC_TRANSIENT_RETRIES" ]; then
      echo "Transient operator RPC read error; backing off ${OPERATOR_RPC_TRANSIENT_BACKOFF_SECONDS}s (attempt $attempt/$OPERATOR_RPC_TRANSIENT_RETRIES)." >&2
      sleep "$OPERATOR_RPC_TRANSIENT_BACKOFF_SECONDS"
      attempt=$((attempt + 1))
      continue
    fi
    printf '%s\n' "$output" >&2
    return "$status"
  done
}

call_market() {
  rpc_read cast call --rpc-url "$RPC_URL" "$MARKET_ADDRESS" "$@"
}

send_market() {
  local private_key="$1"
  shift

  local send_args=(
    --rpc-url "$RPC_URL"
    --chain "$CHAIN_ID"
    --private-key "$private_key"
  )

  if [ -n "$OPERATOR_GAS_PRICE" ]; then
    send_args+=(--gas-price "$OPERATOR_GAS_PRICE")
  fi

  if [ -n "${OPERATOR_PRIORITY_GAS_PRICE:-}" ]; then
    send_args+=(--priority-gas-price "$OPERATOR_PRIORITY_GAS_PRICE")
  fi

  cast send \
    "${send_args[@]}" \
    "$MARKET_ADDRESS" \
    "$@"
}

to_decimal() {
  cast to-dec "$1"
}

current_round_id() {
  call_market "currentRoundId()(uint256)" | first_uint
}

current_operator() {
  call_market "operator()(address)"
}

chain_timestamp() {
  rpc_read cast block latest --field timestamp --rpc-url "$RPC_URL" | first_uint
}

load_round() {
  local round_id="$1"
  local csv
  csv="$(call_market \
    "rounds(uint256)((uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool))" \
    "$round_id" | tr -d '() ')"
  IFS=, read -r \
    ROUND_STATE \
    ROUND_OUTCOME \
    ROUND_START_TIME \
    ROUND_STOP_BET_TIME \
    ROUND_SETTLE_TIME \
    ROUND_BASE_PRICE_E8 \
    ROUND_FINAL_PRICE_E8 \
    ROUND_UP_POOL \
    ROUND_DOWN_POOL \
    ROUND_UP_SHARES \
    ROUND_DOWN_SHARES \
    ROUND_FEE_AMOUNT \
    ROUND_CLEANUP_INDEX \
    ROUND_FEE_TRANSFERRED <<< "$csv"
}

state_name() {
  case "$1" in
    0) echo "None" ;;
    1) echo "Betting" ;;
    2) echo "BettingClosed" ;;
    3) echo "Settled" ;;
    4) echo "Cleaned" ;;
    *) echo "Unknown($1)" ;;
  esac
}

print_status() {
  require_env MARKET_ADDRESS
  local round_id
  round_id="$(current_round_id)"
  local operator_addr
  operator_addr="$(current_operator)"
  echo "market=$MARKET_ADDRESS"
  echo "operator=$operator_addr"
  echo "currentRoundId=$round_id"

  if [ "$round_id" = "0" ]; then
    return
  fi

  local participant_count now
  load_round "$round_id"
  participant_count="$(call_market "participantCount(uint256)(uint256)" "$round_id" | first_uint)"
  now="$(chain_timestamp)"

  echo "state=$(state_name "$ROUND_STATE")"
  echo "stopBetTime=$ROUND_STOP_BET_TIME"
  echo "settleTime=$ROUND_SETTLE_TIME"
  echo "participantCount=$participant_count"
  echo "cleanupIndex=$ROUND_CLEANUP_INDEX"
  echo "now=$now"
}

set_operator() {
  require_env MARKET_ADDRESS
  require_env ADMIN_PRIVATE_KEY
  require_env OPERATOR_ADDRESS

  local current
  current="$(current_operator)"
  if [ "${current,,}" = "${OPERATOR_ADDRESS,,}" ]; then
    echo "Operator already set: $OPERATOR_ADDRESS"
    return
  fi

  echo "Setting operator to $OPERATOR_ADDRESS"
  send_market "$ADMIN_PRIVATE_KEY" "setOperator(address)" "$OPERATOR_ADDRESS"
}

tick() {
  require_env MARKET_ADDRESS
  require_env OPERATOR_PRIVATE_KEY

  local round_id
  round_id="$(current_round_id)"
  if [ "$round_id" = "0" ]; then
    echo "No round exists; starting round."
    send_market "$OPERATOR_PRIVATE_KEY" "startRound()"
    return
  fi

  local now
  load_round "$round_id"
  now="$(chain_timestamp)"
  if ! is_uint "$ROUND_STATE" || ! is_uint "$now"; then
    echo "Unable to read round state or chain timestamp; state=$ROUND_STATE now=$now."
    return
  fi

  case "$ROUND_STATE" in
    1)
      if ! is_uint "$ROUND_STOP_BET_TIME"; then
        echo "Unable to read stopBetTime for round $round_id; stopBetTime=$ROUND_STOP_BET_TIME now=$now."
        return
      fi
      if [ "$now" -ge "$ROUND_STOP_BET_TIME" ]; then
        echo "Round $round_id betting window elapsed; stopping bets."
        send_market "$OPERATOR_PRIVATE_KEY" "stopBet()"
      else
        echo "Round $round_id is betting; stopBetTime=$ROUND_STOP_BET_TIME now=$now."
      fi
      ;;
    2)
      if ! is_uint "$ROUND_SETTLE_TIME"; then
        echo "Unable to read settleTime for round $round_id; settleTime=$ROUND_SETTLE_TIME now=$now."
        return
      fi
      if [ "$now" -ge "$ROUND_SETTLE_TIME" ]; then
        echo "Round $round_id settle time reached; settling."
        send_market "$OPERATOR_PRIVATE_KEY" "settle()"
      else
        echo "Round $round_id is closed; settleTime=$ROUND_SETTLE_TIME now=$now."
      fi
      ;;
    3)
      echo "Round $round_id is settled; cleaning up to $CLEANUP_BATCH_SIZE accounts."
      send_market "$OPERATOR_PRIVATE_KEY" "cleanup(uint256,uint256)" "$round_id" "$CLEANUP_BATCH_SIZE"
      ;;
    4)
      echo "Round $round_id is cleaned; starting next round."
      send_market "$OPERATOR_PRIVATE_KEY" "startRound()"
      ;;
    *)
      echo "Round $round_id has unsupported state $(state_name "$ROUND_STATE"); no action."
      ;;
  esac
}

loop() {
  while true; do
    date -u +"operator tick at %Y-%m-%dT%H:%M:%SZ"
    if ! tick; then
      echo "tick failed; will retry after ${OPERATOR_TICK_SECONDS}s"
    fi
    sleep "$OPERATOR_TICK_SECONDS"
  done
}

case "$ACTION" in
  status)
    print_status
    ;;
  set-operator)
    set_operator
    ;;
  tick)
    tick
    ;;
  loop)
    loop
    ;;
  *)
    echo "Usage: $0 [status|set-operator|tick|loop]"
    exit 1
    ;;
esac
