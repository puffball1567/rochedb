#!/usr/bin/env bash
set -euo pipefail

N="${N:-100000}"
RINGS="${RINGS:-100}"
QUERIES="${QUERIES:-50}"
BUDGET="${BUDGET:-20}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-512}"
RUN_REDIS="${RUN_REDIS:-1}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
CONTAINER_NAME="${CONTAINER_NAME:-roche-memory-case-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release --nimcache:/tmp/nimcache_rochecli_case -o:bin/rochecli src/rochecli.nim

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== RocheDB memory pressure case study =="
echo "n=$N rings=$RINGS queries=$QUERIES budget=$BUDGET payload=${PAYLOAD_BYTES}B"
echo

bin/rochecli memory-pressure-bench \
  --n="$N" \
  --rings="$RINGS" \
  --queries="$QUERIES" \
  --budget="$BUDGET" \
  --payload-bytes="$PAYLOAD_BYTES"

echo
echo "== Redis smoke comparison (optional) =="
if [[ "$RUN_REDIS" != "1" ]]; then
  echo "skipped: RUN_REDIS=$RUN_REDIS"
  exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "skipped: docker command not found"
  exit 0
fi

cleanup
docker run -d --rm --network host --name "$CONTAINER_NAME" "$REDIS_IMAGE" >/dev/null
for _ in {1..50}; do
  if docker exec "$CONTAINER_NAME" redis-cli ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

bin/rochecli redis-bench \
  --n="${REDIS_N:-1000}" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="127.0.0.1:${REDIS_PORT}"
