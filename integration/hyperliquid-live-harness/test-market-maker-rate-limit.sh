#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/cast" <<'FAKE_CAST'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${FAKE_CAST_STATE_DIR:?}"
mkdir -p "$STATE_DIR"
args="$*"

count_call() {
  local name="$1"
  local file="$STATE_DIR/$name"
  local count=0
  if [ -f "$file" ]; then
    count="$(cat "$file")"
  fi
  count=$((count + 1))
  printf '%s' "$count" > "$file"
  echo "$count"
}

if [ "${1:-}" = "block-number" ]; then
  count="$(count_call block_number)"
  if [ "$count" -eq 1 ]; then
    echo "Error: Max retries exceeded server returned an error response: error code -32005: rate limited" >&2
    exit 1
  fi
  echo "34347884"
  exit 0
fi

if [ "${1:-}" = "logs" ]; then
  count="$(count_call logs)"
  if [ "$count" -eq 1 ]; then
    echo "Error: Max retries exceeded server returned an error response: error code -32005: rate limited" >&2
    exit 1
  fi
  echo "[]"
  exit 0
fi

if [ "${1:-}" = "call" ]; then
  case "$args" in
    *"currentRoundId()(uint256)"*)
      echo "2"
      ;;
    *"rounds(uint256)"*)
      echo "(1, 0, 1, 9999999999, 9999999999, 1000000000000, 0, 0, 0, 0, 0, 0, 0, false)"
      ;;
    *"participants(uint256)(address[])"*)
      echo "[]"
      ;;
    *"participantCount(uint256)(uint256)"*)
      echo "0"
      ;;
    *)
      echo "0"
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "block" ]; then
  echo "1"
  exit 0
fi

if [ "${1:-}" = "balance" ]; then
  echo "0"
  exit 0
fi

echo "unexpected fake cast args: $args" >&2
exit 1
FAKE_CAST
chmod +x "$TMP_DIR/bin/cast"

set +e
output="$(
  PATH="$TMP_DIR/bin:$PATH" \
  FAKE_CAST_STATE_DIR="$TMP_DIR/state" \
  RPC_URL="http://fake.invalid" \
  CHAIN_ID="999" \
  MARKET_ADDRESS="0x0000000000000000000000000000000000000001" \
  STAKE_TOKEN="0x0000000000000000000000000000000000000002" \
  COLLECTOR_ADDRESS="0x0000000000000000000000000000000000000003" \
  COLLECTOR_PRIVATE_KEY="0x01" \
  MAKER_1_ADDRESS="0x0000000000000000000000000000000000000011" \
  MAKER_1_PRIVATE_KEY="0x11" \
  MAKER_2_ADDRESS="0x0000000000000000000000000000000000000012" \
  MAKER_2_PRIVATE_KEY="0x12" \
  MAKER_3_ADDRESS="0x0000000000000000000000000000000000000013" \
  MAKER_3_PRIVATE_KEY="0x13" \
  MAKER_4_ADDRESS="0x0000000000000000000000000000000000000014" \
  MAKER_4_PRIVATE_KEY="0x14" \
  MAKER_5_ADDRESS="0x0000000000000000000000000000000000000015" \
  MAKER_5_PRIVATE_KEY="0x15" \
  MAKER_6_ADDRESS="0x0000000000000000000000000000000000000016" \
  MAKER_6_PRIVATE_KEY="0x16" \
  WATCH_MODE="logs" \
  EVENT_POLL_SECONDS="1" \
  POLL_SECONDS="60" \
  RPC_TRANSIENT_RETRIES="2" \
  RPC_TRANSIENT_BACKOFF_SECONDS="1" \
  timeout 5s "$ROOT_DIR/integration/hyperliquid-live-harness/market-maker.sh" loop 2>&1
)"
status=$?
set -e

if [ "$status" -ne 124 ]; then
  printf '%s\n' "$output"
  echo "Expected loop to survive transient RPC rate limits until timeout; status=$status" >&2
  exit 1
fi

if ! printf '%s\n' "$output" | grep -q "Transient RPC read error"; then
  printf '%s\n' "$output"
  echo "Expected transient RPC retry message." >&2
  exit 1
fi

echo "market-maker rate-limit retry test passed"
