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
OPERATOR_TICK_SECONDS="${OPERATOR_TICK_SECONDS:-15}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: $name"
    exit 1
  fi
}

call_market() {
  cast call --rpc-url "$RPC_URL" "$MARKET_ADDRESS" "$@"
}

send_market() {
  local private_key="$1"
  shift
  cast send \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --private-key "$private_key" \
    "$MARKET_ADDRESS" \
    "$@"
}

to_decimal() {
  cast to-dec "$1"
}

current_round_id() {
  call_market "currentRoundId()(uint256)"
}

current_operator() {
  call_market "operator()(address)"
}

chain_timestamp() {
  cast block latest --field timestamp --rpc-url "$RPC_URL"
}

round_field() {
  local round_id="$1"
  local field="$2"
  local index
  case "$field" in
    state) index=1 ;;
    outcome) index=2 ;;
    startTime) index=3 ;;
    stopBetTime) index=4 ;;
    settleTime) index=5 ;;
    basePriceE8) index=6 ;;
    finalPriceE8) index=7 ;;
    upPool) index=8 ;;
    downPool) index=9 ;;
    upShares) index=10 ;;
    downShares) index=11 ;;
    feeAmount) index=12 ;;
    cleanupIndex) index=13 ;;
    feeTransferred) index=14 ;;
    *)
      echo "Unknown round field: $field" >&2
      exit 1
      ;;
  esac

  call_market \
    "rounds(uint256)((uint8,uint8,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,bool))" \
    "$round_id" | tr -d '() ' | awk -F, -v index="$index" '{print $index}'
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

  local state stop_time settle_time cleanup_index participant_count now
  state="$(round_field "$round_id" state)"
  stop_time="$(round_field "$round_id" stopBetTime)"
  settle_time="$(round_field "$round_id" settleTime)"
  cleanup_index="$(round_field "$round_id" cleanupIndex)"
  participant_count="$(call_market "participantCount(uint256)(uint256)" "$round_id")"
  now="$(chain_timestamp)"

  echo "state=$(state_name "$state")"
  echo "stopBetTime=$stop_time"
  echo "settleTime=$settle_time"
  echo "participantCount=$participant_count"
  echo "cleanupIndex=$cleanup_index"
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

  local state now
  state="$(round_field "$round_id" state)"
  now="$(chain_timestamp)"

  case "$state" in
    1)
      local stop_time
      stop_time="$(round_field "$round_id" stopBetTime)"
      if [ "$now" -ge "$stop_time" ]; then
        echo "Round $round_id betting window elapsed; stopping bets."
        send_market "$OPERATOR_PRIVATE_KEY" "stopBet()"
      else
        echo "Round $round_id is betting; stopBetTime=$stop_time now=$now."
      fi
      ;;
    2)
      local settle_time
      settle_time="$(round_field "$round_id" settleTime)"
      if [ "$now" -ge "$settle_time" ]; then
        echo "Round $round_id settle time reached; settling."
        send_market "$OPERATOR_PRIVATE_KEY" "settle()"
      else
        echo "Round $round_id is closed; settleTime=$settle_time now=$now."
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
      echo "Round $round_id has unsupported state $(state_name "$state"); no action."
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
