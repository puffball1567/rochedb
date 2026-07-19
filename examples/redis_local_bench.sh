#!/usr/bin/env bash
set -euo pipefail

N="${N:-1000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_ENDPOINT="${REDIS_ENDPOINT:-127.0.0.1:6379}"
ORBELIASD_PEERS="${ORBELIASD_PEERS:-127.0.0.1:17301}"
DATA="${TMPDIR:-/tmp}/orbeliasdb-redis-local-bench-$$"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORBELIASD_PID=""

cleanup() {
  if [[ -n "$ORBELIASD_PID" ]]; then
    kill "$ORBELIASD_PID" >/dev/null 2>&1 || true
    wait "$ORBELIASD_PID" >/dev/null 2>&1 || true
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

echo "[redis-local-bench] build OrbeliasDB binaries"
nim c -d:release --nimcache:/tmp/nimcache_orbeliasd -o:bin/orbeliasd src/orbeliasd.nim
nim c -d:release --nimcache:/tmp/nimcache_orbeliascli -o:bin/orbelias src/orbeliascli.nim

echo "[redis-local-bench] start one local orbeliasd on $ORBELIASD_PEERS"
bin/orbeliasd --id=0 --peers="$ORBELIASD_PEERS" --data="$DATA/node0" &
ORBELIASD_PID="$!"

for _ in $(seq 1 50); do
  if bin/orbelias health --peers="$ORBELIASD_PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
bin/orbelias health --peers="$ORBELIASD_PEERS" >/dev/null

echo "[redis-local-bench] run OrbeliasDB/Redis benchmark"
bin/orbelias redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  --peers="$ORBELIASD_PEERS"
