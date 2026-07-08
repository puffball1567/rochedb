#!/usr/bin/env bash
set -euo pipefail

N="${N:-1000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_ENDPOINT="${REDIS_ENDPOINT:-127.0.0.1:6379}"
ROCHED_PEERS="${ROCHED_PEERS:-127.0.0.1:17301}"
DATA="${TMPDIR:-/tmp}/rochedb-redis-local-bench-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROCHED_PID=""

cleanup() {
  if [[ -n "$ROCHED_PID" ]]; then
    kill "$ROCHED_PID" >/dev/null 2>&1 || true
    wait "$ROCHED_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

if ! command -v nim >/dev/null 2>&1; then
  echo "missing required command: nim" >&2
  exit 127
fi
if command -v redis-cli >/dev/null 2>&1; then
  redis-cli -h "${REDIS_ENDPOINT%:*}" -p "${REDIS_ENDPOINT##*:}" ping >/dev/null
fi

cd "$ROOT"
mkdir -p "$DATA" bin

echo "[redis-local-bench] build RocheDB binaries"
nim c -d:release --nimcache:/tmp/nimcache_roched -o:bin/roched src/roched.nim
nim c -d:release --nimcache:/tmp/nimcache_rochecli -o:bin/roche src/rochecli.nim

echo "[redis-local-bench] start one local roched on $ROCHED_PEERS"
bin/roched --id=0 --peers="$ROCHED_PEERS" --data="$DATA/node0" &
ROCHED_PID="$!"

for _ in $(seq 1 50); do
  if bin/roche health --peers="$ROCHED_PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
bin/roche health --peers="$ROCHED_PEERS" >/dev/null

echo "[redis-local-bench] run RocheDB/Redis benchmark"
bin/roche redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  --peers="$ROCHED_PEERS"
