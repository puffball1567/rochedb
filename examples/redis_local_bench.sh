#!/usr/bin/env bash
set -euo pipefail

N="${N:-1000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_ENDPOINT="${REDIS_ENDPOINT:-127.0.0.1:6379}"
KOUTEND_PEERS="${KOUTEND_PEERS:-127.0.0.1:17301}"
DATA="${TMPDIR:-/tmp}/koutendb-redis-local-bench-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOUTEND_PID=""

cleanup() {
  if [[ -n "$KOUTEND_PID" ]]; then
    kill "$KOUTEND_PID" >/dev/null 2>&1 || true
    wait "$KOUTEND_PID" >/dev/null 2>&1 || true
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

echo "[redis-local-bench] build KoutenDB binaries"
nim c -d:release --nimcache:/tmp/nimcache_koutend -o:bin/koutend src/koutend.nim
nim c -d:release --nimcache:/tmp/nimcache_koutencli -o:bin/kouten src/koutencli.nim

echo "[redis-local-bench] start one local koutend on $KOUTEND_PEERS"
bin/koutend --id=0 --peers="$KOUTEND_PEERS" --data="$DATA/node0" &
KOUTEND_PID="$!"

for _ in $(seq 1 50); do
  if bin/kouten health --peers="$KOUTEND_PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
bin/kouten health --peers="$KOUTEND_PEERS" >/dev/null

echo "[redis-local-bench] run KoutenDB/Redis benchmark"
bin/kouten redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  --peers="$KOUTEND_PEERS"
