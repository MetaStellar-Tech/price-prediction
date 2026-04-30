#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_DIR="$ROOT_DIR/integration/hyperliquid-live-harness"
ENV_FILE="${ENV_FILE:-$HARNESS_DIR/.market-maker.env}"
ROOT_ENV_FILE="${ROOT_ENV_FILE:-$ROOT_DIR/.env}"
ACTION="${1:-status}"

if [ -f "$ROOT_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ROOT_ENV_FILE"
  set +a
fi

if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

RPC_URL="${RPC_URL:-https://rpc.hyperliquid.xyz/evm}"
CHAIN_ID="${CHAIN_ID:-999}"
MARKET_ADDRESS="${MARKET_ADDRESS:-}"
STAKE_TOKEN="${STAKE_TOKEN:-}"
USDC_DECIMALS="${USDC_DECIMALS:-6}"
MAKER_TARGET_USDC="${MAKER_TARGET_USDC:-10000000}"
MAKER_LOW_WATER_USDC="${MAKER_LOW_WATER_USDC:-8000000}"
MAKER_HIGH_WATER_USDC="${MAKER_HIGH_WATER_USDC:-15000000}"
MAKER_TARGET_HYPE_WEI="${MAKER_TARGET_HYPE_WEI:-20000000000000000}"
MAKER_MAX_ROUND_USDC="${MAKER_MAX_ROUND_USDC:-6000000}"
TOTAL_MAX_ROUND_USDC="${TOTAL_MAX_ROUND_USDC:-24000000}"
MIN_BET_USDC="${MIN_BET_USDC:-1000000}"
NORMAL_MAX_BET_USDC="${NORMAL_MAX_BET_USDC:-3000000}"
SEVERE_MAX_BET_USDC="${SEVERE_MAX_BET_USDC:-10000000}"
ROUND_POOL_TARGET_BPS="${ROUND_POOL_TARGET_BPS:-6000}"
MAKER_EXPOSURE_MIN_BPS="${MAKER_EXPOSURE_MIN_BPS:-4000}"
MAKER_EXPOSURE_MAX_BPS="${MAKER_EXPOSURE_MAX_BPS:-6000}"
SLIPPAGE_BPS="${SLIPPAGE_BPS:-500}"
POLL_SECONDS="${POLL_SECONDS:-12}"
MIN_MAKER_DELAY_SECONDS="${MIN_MAKER_DELAY_SECONDS:-2}"
MAX_MAKER_DELAY_SECONDS="${MAX_MAKER_DELAY_SECONDS:-12}"
CLEANUP_BATCH_SIZE="${CLEANUP_BATCH_SIZE:-50}"
EVENT_FROM_BLOCK="${EVENT_FROM_BLOCK:-33813039}"
EVENT_TO_BLOCK="${EVENT_TO_BLOCK:-latest}"
CAST_SEND_ASYNC="${CAST_SEND_ASYNC:-1}"
GAS_PRICE_WEI="${GAS_PRICE_WEI:-3100000000}"
MARKET_GAS_LIMIT="${MARKET_GAS_LIMIT:-500000}"
TOKEN_GAS_LIMIT="${TOKEN_GAS_LIMIT:-80000}"
HYPE_TRANSFER_GAS_LIMIT="${HYPE_TRANSFER_GAS_LIMIT:-21000}"

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required env var: $name"
    exit 1
  fi
}

require_runtime_env() {
  require_env RPC_URL
  require_env CHAIN_ID
  require_env MARKET_ADDRESS
  require_env STAKE_TOKEN
}

require_wallet_env() {
  require_env COLLECTOR_ADDRESS
  require_env COLLECTOR_PRIVATE_KEY
  local i
  for i in 1 2 3 4 5 6; do
    require_env "MAKER_${i}_ADDRESS"
    require_env "MAKER_${i}_PRIVATE_KEY"
  done
}

load_makers() {
  MAKER_ADDRESSES=()
  MAKER_PRIVATE_KEYS=()
  local i addr key addr_var key_var
  for i in 1 2 3 4 5 6; do
    addr_var="MAKER_${i}_ADDRESS"
    key_var="MAKER_${i}_PRIVATE_KEY"
    addr="${!addr_var:-}"
    key="${!key_var:-}"
    if [ -n "$addr" ]; then
      MAKER_ADDRESSES+=("$addr")
      MAKER_PRIVATE_KEYS+=("$key")
    fi
  done
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_maker() {
  local target
  target="$(lower "$1")"
  local addr
  for addr in "${MAKER_ADDRESSES[@]:-}"; do
    if [ "$(lower "$addr")" = "$target" ]; then
      return 0
    fi
  done
  return 1
}

rand_range() {
  local min="$1"
  local max="$2"
  if [ "$max" -le "$min" ]; then
    echo "$min"
    return
  fi
  echo $((min + RANDOM % (max - min + 1)))
}

format_usdc() {
  awk -v amount="$1" -v decimals="$USDC_DECIMALS" 'BEGIN {
    scale = 1;
    for (i = 0; i < decimals; i++) scale *= 10;
    printf "%.6f", amount / scale;
  }'
}

format_wei() {
  awk -v amount="$1" 'BEGIN { printf "%.8f", amount / 1000000000000000000; }'
}

call_market() {
  cast call --rpc-url "$RPC_URL" "$MARKET_ADDRESS" "$@"
}

send_mode_args() {
  if [ "$CAST_SEND_ASYNC" = "1" ]; then
    printf '%s\n' "--async"
  fi
}

send_market() {
  local private_key="$1"
  shift
  cast send \
    $(send_mode_args) \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --gas-price "$GAS_PRICE_WEI" \
    --gas-limit "$MARKET_GAS_LIMIT" \
    --private-key "$private_key" \
    "$MARKET_ADDRESS" \
    "$@"
}

call_token() {
  cast call --rpc-url "$RPC_URL" "$STAKE_TOKEN" "$@"
}

send_token() {
  local private_key="$1"
  shift
  cast send \
    $(send_mode_args) \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --gas-price "$GAS_PRICE_WEI" \
    --gas-limit "$TOKEN_GAS_LIMIT" \
    --private-key "$private_key" \
    "$STAKE_TOKEN" \
    "$@"
}

send_hype() {
  local private_key="$1"
  local to="$2"
  local amount="$3"
  cast send \
    $(send_mode_args) \
    --rpc-url "$RPC_URL" \
    --chain "$CHAIN_ID" \
    --gas-price "$GAS_PRICE_WEI" \
    --gas-limit "$HYPE_TRANSFER_GAS_LIMIT" \
    --private-key "$private_key" \
    --value "$amount" \
    "$to"
}

current_round_id() {
  call_market "currentRoundId()(uint256)"
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

outcome_name() {
  case "$1" in
    0) echo "None" ;;
    1) echo "Up" ;;
    2) echo "Down" ;;
    3) echo "Draw" ;;
    4) echo "NoContest" ;;
    *) echo "Unknown($1)" ;;
  esac
}

participant_count() {
  call_market "participantCount(uint256)(uint256)" "$1"
}

participants() {
  call_market "participants(uint256)(address[])" "$1" | tr -d '[],' | tr ' ' '\n' | sed '/^$/d'
}

position_field() {
  local round_id="$1"
  local account="$2"
  local field="$3"
  local index
  case "$field" in
    upStake) index=1 ;;
    downStake) index=2 ;;
    upShares) index=3 ;;
    downShares) index=4 ;;
    *)
      echo "Unknown position field: $field" >&2
      exit 1
      ;;
  esac

  call_market "positions(uint256,address)((uint256,uint256,uint256,uint256))" "$round_id" "$account" \
    | tr -d '() ' | awk -F, -v index="$index" '{print $index}'
}

token_balance() {
  call_token "balanceOf(address)(uint256)" "$1"
}

native_balance() {
  cast balance --rpc-url "$RPC_URL" "$1"
}

allowance() {
  call_token "allowance(address,address)(uint256)" "$1" "$MARKET_ADDRESS"
}

init_wallets() {
  if [ -f "$ENV_FILE" ]; then
    echo "Wallet env already exists: $ENV_FILE"
    echo "Refusing to overwrite reusable private keys."
    exit 1
  fi

  mkdir -p "$HARNESS_DIR"
  umask 077
  {
    echo "# Generated by market-maker.sh init-wallets on $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "# Never commit this file."
    echo "RPC_URL=${RPC_URL}"
    echo "CHAIN_ID=${CHAIN_ID}"
    echo "MARKET_ADDRESS=${MARKET_ADDRESS:-0x406661e7AeF968441d53bc9557be3a8FAa92A67B}"
    echo "STAKE_TOKEN=${STAKE_TOKEN:-0xb88339CB7199b77E23DB6E890353E22632Ba630f}"
    echo
  } > "$ENV_FILE"

  local wallet address key i
  wallet="$(cast wallet new)"
  address="$(printf '%s\n' "$wallet" | awk '/Address:/ {print $2}')"
  key="$(printf '%s\n' "$wallet" | awk '/Private key:/ {print $3}')"
  {
    echo "COLLECTOR_ADDRESS=$address"
    echo "COLLECTOR_PRIVATE_KEY=$key"
    echo
  } >> "$ENV_FILE"

  for i in 1 2 3 4 5 6; do
    wallet="$(cast wallet new)"
    address="$(printf '%s\n' "$wallet" | awk '/Address:/ {print $2}')"
    key="$(printf '%s\n' "$wallet" | awk '/Private key:/ {print $3}')"
    {
      echo "MAKER_${i}_ADDRESS=$address"
      echo "MAKER_${i}_PRIVATE_KEY=$key"
    } >> "$ENV_FILE"
  done

  cat >> "$ENV_FILE" <<EOF

USDC_DECIMALS=$USDC_DECIMALS
MAKER_TARGET_USDC=$MAKER_TARGET_USDC
MAKER_LOW_WATER_USDC=$MAKER_LOW_WATER_USDC
MAKER_HIGH_WATER_USDC=$MAKER_HIGH_WATER_USDC
MAKER_TARGET_HYPE_WEI=$MAKER_TARGET_HYPE_WEI
MAKER_MAX_ROUND_USDC=$MAKER_MAX_ROUND_USDC
TOTAL_MAX_ROUND_USDC=$TOTAL_MAX_ROUND_USDC
MIN_BET_USDC=$MIN_BET_USDC
NORMAL_MAX_BET_USDC=$NORMAL_MAX_BET_USDC
SEVERE_MAX_BET_USDC=$SEVERE_MAX_BET_USDC
ROUND_POOL_TARGET_BPS=$ROUND_POOL_TARGET_BPS
MAKER_EXPOSURE_MIN_BPS=$MAKER_EXPOSURE_MIN_BPS
MAKER_EXPOSURE_MAX_BPS=$MAKER_EXPOSURE_MAX_BPS
SLIPPAGE_BPS=$SLIPPAGE_BPS
POLL_SECONDS=$POLL_SECONDS
MIN_MAKER_DELAY_SECONDS=$MIN_MAKER_DELAY_SECONDS
MAX_MAKER_DELAY_SECONDS=$MAX_MAKER_DELAY_SECONDS
CLEANUP_BATCH_SIZE=$CLEANUP_BATCH_SIZE
EVENT_FROM_BLOCK=$EVENT_FROM_BLOCK
EVENT_TO_BLOCK=$EVENT_TO_BLOCK
CAST_SEND_ASYNC=$CAST_SEND_ASYNC
GAS_PRICE_WEI=$GAS_PRICE_WEI
MARKET_GAS_LIMIT=$MARKET_GAS_LIMIT
TOKEN_GAS_LIMIT=$TOKEN_GAS_LIMIT
HYPE_TRANSFER_GAS_LIMIT=$HYPE_TRANSFER_GAS_LIMIT
EOF

  chmod 600 "$ENV_FILE"
  echo "Created wallet env: $ENV_FILE"
  echo "Collector address:"
  grep '^COLLECTOR_ADDRESS=' "$ENV_FILE" | cut -d= -f2-
}

print_wallet_line() {
  local label="$1"
  local address="$2"
  local usdc hype approval
  usdc="$(token_balance "$address")"
  hype="$(native_balance "$address")"
  approval="$(allowance "$address")"
  printf '%-12s %s usdc=%s hype=%s allowance=%s\n' \
    "$label" "$address" "$(format_usdc "$usdc")" "$(format_wei "$hype")" "$(format_usdc "$approval")"
}

status() {
  require_runtime_env
  require_wallet_env
  load_makers

  local round_id state
  round_id="$(current_round_id)"
  echo "market=$MARKET_ADDRESS"
  echo "stakeToken=$STAKE_TOKEN"
  echo "currentRoundId=$round_id"
  if [ "$round_id" != "0" ]; then
    state="$(round_field "$round_id" state)"
    echo "state=$(state_name "$state")"
    echo "upPool=$(format_usdc "$(round_field "$round_id" upPool)")"
    echo "downPool=$(format_usdc "$(round_field "$round_id" downPool)")"
    echo "participantCount=$(participant_count "$round_id")"
  fi
  echo
  print_wallet_line "collector" "$COLLECTOR_ADDRESS"
  local i
  for i in "${!MAKER_ADDRESSES[@]}"; do
    print_wallet_line "maker_$((i + 1))" "${MAKER_ADDRESSES[$i]}"
  done
}

fund() {
  require_runtime_env
  require_wallet_env
  load_makers

  local i addr usdc hype usdc_needed hype_needed
  for i in "${!MAKER_ADDRESSES[@]}"; do
    addr="${MAKER_ADDRESSES[$i]}"
    usdc="$(token_balance "$addr")"
    hype="$(native_balance "$addr")"
    if [ "$usdc" -lt "$MAKER_TARGET_USDC" ]; then
      usdc_needed=$((MAKER_TARGET_USDC - usdc))
      echo "Funding maker_$((i + 1)) USDC $(format_usdc "$usdc_needed")"
      send_token "$COLLECTOR_PRIVATE_KEY" "transfer(address,uint256)" "$addr" "$usdc_needed"
    fi
    if [ "$hype" -lt "$MAKER_TARGET_HYPE_WEI" ]; then
      hype_needed=$((MAKER_TARGET_HYPE_WEI - hype))
      echo "Funding maker_$((i + 1)) HYPE $(format_wei "$hype_needed")"
      send_hype "$COLLECTOR_PRIVATE_KEY" "$addr" "$hype_needed"
    fi
  done
}

approve() {
  require_runtime_env
  require_wallet_env
  load_makers

  local i key approval max_approval
  max_approval="1000000000000"
  for i in "${!MAKER_ADDRESSES[@]}"; do
    approval="$(allowance "${MAKER_ADDRESSES[$i]}")"
    if [ "$approval" -lt "$MAKER_HIGH_WATER_USDC" ]; then
      key="${MAKER_PRIVATE_KEYS[$i]}"
      echo "Approving maker_$((i + 1)) for market USDC spending."
      send_token "$key" "approve(address,uint256)" "$MARKET_ADDRESS" "$max_approval"
    fi
  done
}

maker_position_totals() {
  local round_id="$1"
  MAKER_UP_STAKE=0
  MAKER_DOWN_STAKE=0
  local addr up down
  for addr in "${MAKER_ADDRESSES[@]}"; do
    up="$(position_field "$round_id" "$addr" upStake)"
    down="$(position_field "$round_id" "$addr" downStake)"
    MAKER_UP_STAKE=$((MAKER_UP_STAKE + up))
    MAKER_DOWN_STAKE=$((MAKER_DOWN_STAKE + down))
  done
}

maker_round_spent() {
  local round_id="$1"
  local addr up down total=0
  for addr in "${MAKER_ADDRESSES[@]}"; do
    up="$(position_field "$round_id" "$addr" upStake)"
    down="$(position_field "$round_id" "$addr" downStake)"
    total=$((total + up + down))
  done
  echo "$total"
}

single_maker_spent() {
  local round_id="$1"
  local addr="$2"
  local up down
  up="$(position_field "$round_id" "$addr" upStake)"
  down="$(position_field "$round_id" "$addr" downStake)"
  echo $((up + down))
}

choose_direction() {
  local round_id="$1"
  local up_pool down_pool maker_total maker_up_bps
  up_pool="$(round_field "$round_id" upPool)"
  down_pool="$(round_field "$round_id" downPool)"
  maker_position_totals "$round_id"
  maker_total=$((MAKER_UP_STAKE + MAKER_DOWN_STAKE))

  if [ "$up_pool" -eq 0 ]; then
    echo 0
    return
  fi
  if [ "$down_pool" -eq 0 ]; then
    echo 1
    return
  fi

  if [ "$up_pool" -gt "$down_pool" ]; then
    if [ $((down_pool * 10000 / up_pool)) -lt "$ROUND_POOL_TARGET_BPS" ]; then
      echo 1
      return
    fi
  elif [ $((up_pool * 10000 / down_pool)) -lt "$ROUND_POOL_TARGET_BPS" ]; then
    echo 0
    return
  fi

  if [ "$maker_total" -gt 0 ]; then
    maker_up_bps=$((MAKER_UP_STAKE * 10000 / maker_total))
    if [ "$maker_up_bps" -lt "$MAKER_EXPOSURE_MIN_BPS" ]; then
      echo 0
      return
    fi
    if [ "$maker_up_bps" -gt "$MAKER_EXPOSURE_MAX_BPS" ]; then
      echo 1
      return
    fi
  fi

  rand_range 0 1
}

amount_cap_for_direction() {
  local direction="$1"
  local up_pool="$2"
  local down_pool="$3"
  local cap severe_cap
  cap="$NORMAL_MAX_BET_USDC"
  severe_cap="$SEVERE_MAX_BET_USDC"

  if [ "$direction" -eq 0 ] && [ "$down_pool" -gt "$up_pool" ]; then
    local target
    target=$((down_pool * ROUND_POOL_TARGET_BPS / 10000))
    if [ "$target" -gt "$up_pool" ]; then
      cap=$((target - up_pool))
    fi
  elif [ "$direction" -eq 1 ] && [ "$up_pool" -gt "$down_pool" ]; then
    local target
    target=$((up_pool * ROUND_POOL_TARGET_BPS / 10000))
    if [ "$target" -gt "$down_pool" ]; then
      cap=$((target - down_pool))
    fi
  fi

  if [ "$cap" -gt "$severe_cap" ]; then
    cap="$severe_cap"
  fi
  if [ "$cap" -lt "$MIN_BET_USDC" ]; then
    cap="$MIN_BET_USDC"
  fi
  echo "$cap"
}

preview_shares() {
  local direction="$1"
  local amount="$2"
  call_market "previewBet(uint8,uint256)(uint256,uint256,uint256,uint256)" "$direction" "$amount" \
    | tr -d '() ' | awk -F, '{print $4}'
}

place_bet() {
  local maker_index="$1"
  local round_id="$2"
  local addr key spent total_spent remaining direction up_pool down_pool cap max_amount amount shares min_shares
  addr="${MAKER_ADDRESSES[$maker_index]}"
  key="${MAKER_PRIVATE_KEYS[$maker_index]}"
  spent="$(single_maker_spent "$round_id" "$addr")"
  total_spent="$(maker_round_spent "$round_id")"
  if [ "$spent" -ge "$MAKER_MAX_ROUND_USDC" ] || [ "$total_spent" -ge "$TOTAL_MAX_ROUND_USDC" ]; then
    return 0
  fi

  remaining=$((MAKER_MAX_ROUND_USDC - spent))
  if [ $((TOTAL_MAX_ROUND_USDC - total_spent)) -lt "$remaining" ]; then
    remaining=$((TOTAL_MAX_ROUND_USDC - total_spent))
  fi
  if [ "$remaining" -lt "$MIN_BET_USDC" ]; then
    return 0
  fi

  direction="$(choose_direction "$round_id")"
  up_pool="$(round_field "$round_id" upPool)"
  down_pool="$(round_field "$round_id" downPool)"
  cap="$(amount_cap_for_direction "$direction" "$up_pool" "$down_pool")"
  max_amount="$cap"
  if [ "$max_amount" -gt "$remaining" ]; then
    max_amount="$remaining"
  fi
  amount="$(rand_range "$MIN_BET_USDC" "$max_amount")"

  shares="$(preview_shares "$direction" "$amount")"
  min_shares=$((shares * (10000 - SLIPPAGE_BPS) / 10000))
  echo "maker_$((maker_index + 1)) bet round=$round_id direction=$direction amount=$(format_usdc "$amount") minShares=$min_shares"
  send_market "$key" "bet(uint8,uint256,uint256)" "$direction" "$amount" "$min_shares"
}

external_participant_count() {
  local round_id="$1"
  local count=0 addr
  while read -r addr; do
    [ -z "$addr" ] && continue
    if ! is_maker "$addr"; then
      count=$((count + 1))
    fi
  done < <(participants "$round_id")
  echo "$count"
}

do_market_make_round() {
  local round_id="$1"
  local i attempts j delay state
  for i in "${!MAKER_ADDRESSES[@]}"; do
    state="$(round_field "$round_id" state)"
    if [ "$state" != "1" ]; then
      echo "Round $round_id no longer betting; stopping maker actions."
      return
    fi
    attempts="$(rand_range 1 3)"
    for ((j = 1; j <= attempts; j++)); do
      place_bet "$i" "$round_id"
      delay="$(rand_range "$MIN_MAKER_DELAY_SECONDS" "$MAX_MAKER_DELAY_SECONDS")"
      sleep "$delay"
      state="$(round_field "$round_id" state)"
      if [ "$state" != "1" ]; then
        return
      fi
    done
  done
}

loop() {
  require_runtime_env
  require_wallet_env
  load_makers

  local last_round=0 last_external=0 round_id state external_count
  while true; do
    round_id="$(current_round_id)"
    if [ "$round_id" = "0" ]; then
      echo "No active round yet; waiting ${POLL_SECONDS}s."
      sleep "$POLL_SECONDS"
      continue
    fi

    state="$(round_field "$round_id" state)"
    if [ "$round_id" != "$last_round" ]; then
      last_round="$round_id"
      last_external=0
      echo "Watching round $round_id state=$(state_name "$state")."
    fi

    if [ "$state" = "1" ]; then
      external_count="$(external_participant_count "$round_id")"
      if [ "$external_count" -gt "$last_external" ]; then
        echo "Detected external participant activity in round $round_id: $external_count"
        last_external="$external_count"
        do_market_make_round "$round_id"
      else
        echo "Round $round_id betting; externalParticipants=$external_count."
      fi
    else
      echo "Round $round_id state=$(state_name "$state"); maker idle."
    fi

    sleep "$POLL_SECONDS"
  done
}

rebalance() {
  require_runtime_env
  require_wallet_env
  load_makers

  local round_id state i addr key usdc excess needed
  round_id="$(current_round_id)"
  state="$(round_field "$round_id" state)"
  if [ "$state" != "4" ]; then
    echo "Round $round_id is $(state_name "$state"); rebalance waits for Cleaned."
    exit 1
  fi

  for i in "${!MAKER_ADDRESSES[@]}"; do
    addr="${MAKER_ADDRESSES[$i]}"
    key="${MAKER_PRIVATE_KEYS[$i]}"
    usdc="$(token_balance "$addr")"
    if [ "$usdc" -gt "$MAKER_HIGH_WATER_USDC" ]; then
      excess=$((usdc - MAKER_TARGET_USDC))
      echo "Sweeping maker_$((i + 1)) excess USDC $(format_usdc "$excess")"
      send_token "$key" "transfer(address,uint256)" "$COLLECTOR_ADDRESS" "$excess"
    elif [ "$usdc" -lt "$MAKER_LOW_WATER_USDC" ]; then
      needed=$((MAKER_TARGET_USDC - usdc))
      echo "Refilling maker_$((i + 1)) USDC $(format_usdc "$needed")"
      send_token "$COLLECTOR_PRIVATE_KEY" "transfer(address,uint256)" "$addr" "$needed"
    fi
  done
}

write_balances() {
  local output="$1"
  {
    print_wallet_line "collector" "$COLLECTOR_ADDRESS"
    local i
    for i in "${!MAKER_ADDRESSES[@]}"; do
      print_wallet_line "maker_$((i + 1))" "${MAKER_ADDRESSES[$i]}"
    done
  } > "$output"
}

write_round_report() {
  local round_id="$1"
  local output="$2"
  {
    echo "roundId=$round_id"
    echo "state=$(state_name "$(round_field "$round_id" state)")"
    echo "outcome=$(outcome_name "$(round_field "$round_id" outcome)")"
    echo "startTime=$(round_field "$round_id" startTime)"
    echo "stopBetTime=$(round_field "$round_id" stopBetTime)"
    echo "settleTime=$(round_field "$round_id" settleTime)"
    echo "basePriceE8=$(round_field "$round_id" basePriceE8)"
    echo "finalPriceE8=$(round_field "$round_id" finalPriceE8)"
    echo "upPool=$(round_field "$round_id" upPool)"
    echo "downPool=$(round_field "$round_id" downPool)"
    echo "upShares=$(round_field "$round_id" upShares)"
    echo "downShares=$(round_field "$round_id" downShares)"
    echo "feeAmount=$(round_field "$round_id" feeAmount)"
    echo "cleanupIndex=$(round_field "$round_id" cleanupIndex)"
    echo "participantCount=$(participant_count "$round_id")"
  } > "$output"
}

write_positions() {
  local round_id="$1"
  local output="$2"
  {
    echo "account,kind,upStake,downStake,upShares,downShares"
    local addr kind
    while read -r addr; do
      [ -z "$addr" ] && continue
      kind="external"
      if is_maker "$addr"; then
        kind="maker"
      fi
      printf '%s,%s,%s,%s,%s,%s\n' \
        "$addr" \
        "$kind" \
        "$(position_field "$round_id" "$addr" upStake)" \
        "$(position_field "$round_id" "$addr" downStake)" \
        "$(position_field "$round_id" "$addr" upShares)" \
        "$(position_field "$round_id" "$addr" downShares)"
    done < <(participants "$round_id")
  } > "$output"
}

write_events() {
  local round_id="$1"
  local output="$2"
  local from_block to_block
  from_block="${FROM_BLOCK:-$EVENT_FROM_BLOCK}"
  to_block="${TO_BLOCK:-$EVENT_TO_BLOCK}"
  if command -v jq >/dev/null 2>&1; then
    cast logs --json --rpc-url "$RPC_URL" --from-block "$from_block" --to-block "$to_block" \
      --address "$MARKET_ADDRESS" | jq -c '.[]' > "$output" || true
  else
    cast logs --json --rpc-url "$RPC_URL" --from-block "$from_block" --to-block "$to_block" \
      --address "$MARKET_ADDRESS" > "$output" || true
  fi
}

review() {
  require_runtime_env
  require_wallet_env
  load_makers

  local round_id run_dir state outcome base final fee up_pool down_pool cleanup_index count
  round_id="${1:-$(current_round_id)}"
  run_dir="$HARNESS_DIR/runs/$(date -u +"%Y%m%dT%H%M%SZ")-round-${round_id}"
  mkdir -p "$run_dir"

  write_balances "$run_dir/balances-after.txt"
  write_round_report "$round_id" "$run_dir/round.txt"
  write_positions "$round_id" "$run_dir/positions.txt"
  write_events "$round_id" "$run_dir/events.jsonl"

  state="$(round_field "$round_id" state)"
  outcome="$(round_field "$round_id" outcome)"
  base="$(round_field "$round_id" basePriceE8)"
  final="$(round_field "$round_id" finalPriceE8)"
  fee="$(round_field "$round_id" feeAmount)"
  up_pool="$(round_field "$round_id" upPool)"
  down_pool="$(round_field "$round_id" downPool)"
  cleanup_index="$(round_field "$round_id" cleanupIndex)"
  count="$(participant_count "$round_id")"
  maker_position_totals "$round_id"

  {
    echo "# Market Maker Review"
    echo
    echo "- roundId: $round_id"
    echo "- state: $(state_name "$state")"
    echo "- outcome: $(outcome_name "$outcome")"
    echo "- basePriceE8: $base"
    echo "- finalPriceE8: $final"
    echo "- upPool: $(format_usdc "$up_pool")"
    echo "- downPool: $(format_usdc "$down_pool")"
    echo "- feeAmount: $(format_usdc "$fee")"
    echo "- participantCount: $count"
    echo "- cleanupIndex: $cleanup_index"
    echo "- makerUpStake: $(format_usdc "$MAKER_UP_STAKE")"
    echo "- makerDownStake: $(format_usdc "$MAKER_DOWN_STAKE")"
    echo
    echo "## Checks"
    if [ "$state" = "4" ] && [ "$cleanup_index" = "$count" ]; then
      echo "- [x] cleanup reached every participant."
    else
      echo "- [ ] WARNING: cleanup is not complete."
    fi
    if { [ "$outcome" = "3" ] || [ "$outcome" = "4" ]; } && [ "$fee" = "0" ]; then
      echo "- [x] draw/no-contest fee is zero."
    elif [ "$outcome" = "3" ] || [ "$outcome" = "4" ]; then
      echo "- [ ] WARNING: draw/no-contest has non-zero fee."
    else
      echo "- [x] non-draw outcome may charge losing-pool fee."
    fi
    if [ "$final" -gt "$base" ] && { [ "$outcome" = "1" ] || [ "$outcome" = "4" ]; }; then
      echo "- [x] outcome matches upward final price or no-contest."
    elif [ "$final" -lt "$base" ] && { [ "$outcome" = "2" ] || [ "$outcome" = "4" ]; }; then
      echo "- [x] outcome matches downward final price or no-contest."
    elif [ "$final" = "$base" ] && [ "$outcome" = "3" ]; then
      echo "- [x] outcome matches draw price."
    else
      echo "- [ ] WARNING: outcome does not match base/final price expectation."
    fi
    if [ $((MAKER_UP_STAKE + MAKER_DOWN_STAKE)) -gt 0 ]; then
      local maker_up_bps
      maker_up_bps=$((MAKER_UP_STAKE * 10000 / (MAKER_UP_STAKE + MAKER_DOWN_STAKE)))
      if [ "$maker_up_bps" -ge "$MAKER_EXPOSURE_MIN_BPS" ] && [ "$maker_up_bps" -le "$MAKER_EXPOSURE_MAX_BPS" ]; then
        echo "- [x] maker exposure is within target band."
      else
        echo "- [ ] WARNING: maker exposure is outside target band."
      fi
    fi
  } > "$run_dir/review.md"

  echo "Review written to $run_dir"
}

usage() {
  cat <<EOF
Usage: $0 [init-wallets|status|fund|approve|loop|rebalance|review [roundId]]

Environment:
  ENV_FILE defaults to $ENV_FILE
  Copy .market-maker.env.example or run init-wallets first.
EOF
}

case "$ACTION" in
  init-wallets)
    init_wallets
    ;;
  status)
    status
    ;;
  fund)
    fund
    ;;
  approve)
    approve
    ;;
  loop)
    loop
    ;;
  rebalance)
    rebalance
    ;;
  review)
    review "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
