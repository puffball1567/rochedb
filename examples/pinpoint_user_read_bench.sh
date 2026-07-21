#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${KOUTEN_PINPOINT_WORKDIR:-}" ]]; then
  WORK="$KOUTEN_PINPOINT_WORKDIR"
else
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/koutendb-pinpoint-read.XXXXXX")"
fi
BIN="$ROOT/bin/pinpoint_user_read_bench"
USERS="${KOUTEN_PINPOINT_USERS:-100000}"
TARGET_INDEX="${KOUTEN_PINPOINT_TARGET_INDEX:-}"
MODE="${KOUTEN_PINPOINT_MODE:-disk}"

cleanup() {
  if [[ "${KEEP_KOUTEN_PINPOINT:-0}" != "1" ]]; then
    rm -rf "$WORK"
  else
    echo "kept workdir: $WORK"
  fi
}
trap cleanup EXIT

mkdir -p "$WORK" "$ROOT/bin"
cd "$ROOT"

echo "== Build pinpoint user read benchmark =="
nim c -d:release --nimcache:/tmp/nimcache_kouten_pinpoint_read \
  -o:"$BIN" examples/pinpoint_user_read_bench.nim >/dev/null

args=(
  "--data=$WORK/data"
  "--users=$USERS"
  "--metrics"
)

if [[ -n "$TARGET_INDEX" ]]; then
  args+=("--target-index=$TARGET_INDEX")
fi

case "$MODE" in
  disk)
    args+=("--disk-backed")
    ;;
  memory)
    args+=("--memory")
    ;;
  *)
    echo "KOUTEN_PINPOINT_MODE must be disk or memory" >&2
    exit 2
    ;;
esac

out="$WORK/metrics.txt"
"$BIN" "${args[@]}" > "$out"

metric() {
  local key="$1"
  awk -v k="$key" '$1 == k { print $2; found=1 } END { if (!found) print "" }' "$out"
}

users="$(metric pinpointUsers)"
target="$(metric pinpointTarget)"
disk="$(metric pinpointDiskBacked)"
broad_set="$(metric pinpointBroadSetLatencyUs)"
broad_set_rec="$(metric pinpointBroadSetUsPerRecord)"
broad_pack="$(metric pinpointBroadPackLatencyUs)"
local_set="$(metric pinpointLocalSetLatencyUs)"
local_set_rec="$(metric pinpointLocalSetUsPerRecord)"
local_pack="$(metric pinpointLocalPackLatencyUs)"
broad_read="$(metric pinpointBroadReadLatencyUs)"
local_read_1="$(metric pinpointLocalReadOneLatencyUs)"
local_read_20="$(metric pinpointLocalReadTwentyLatencyUs)"

echo
echo "== KoutenDB pinpoint user read benchmark =="
echo "users: $users"
echo "target: $target"
echo "disk backed: $disk"
echo
echo "| layout | set latency us | set us/record | pack latency us | read mode | read latency us |"
echo "| --- | ---: | ---: | ---: | --- | ---: |"
echo "| broad users ring | $broad_set | $broad_set_rec | $broad_pack | filter id in users | $broad_read |"
echo "| local users/<id> ring | $local_set | $local_set_rec | $local_pack | read users/<id> limit=1 | $local_read_1 |"
echo "| local users/<id> ring | $local_set | $local_set_rec | $local_pack | read users/<id> limit=20 | $local_read_20 |"
echo
echo "Set KOUTEN_PINPOINT_USERS=N to control user count."
echo "Set KOUTEN_PINPOINT_MODE=disk or memory."
echo "Set KOUTEN_PINPOINT_TARGET_INDEX=N to choose the target user."
