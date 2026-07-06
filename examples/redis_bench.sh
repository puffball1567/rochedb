#!/usr/bin/env bash
set -euo pipefail

N="${N:-100000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
CONTAINER_NAME="${CONTAINER_NAME:-roche-redis-bench}"
NETWORK_MODE="${NETWORK_MODE:-host}"
REDIS_PORT="${REDIS_PORT:-6379}"
ROCHED="${ROCHED:-0}"
ROCHED_PEERS="${ROCHED_PEERS:-127.0.0.1:17301}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release -o:bin/rochecli src/rochecli.nim
if [[ "$ROCHED" == "1" ]]; then
  nim c -d:release -o:bin/roched src/roched.nim
fi

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  if [[ -n "${ROCHED_PID:-}" ]]; then
    kill "$ROCHED_PID" >/dev/null 2>&1 || true
    wait "$ROCHED_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cleanup

if [[ "$NETWORK_MODE" == "host" ]]; then
  docker run -d --rm --network host --name "$CONTAINER_NAME" "$REDIS_IMAGE" >/dev/null
  REDIS_ENDPOINT="127.0.0.1:${REDIS_PORT}"
else
  docker run -d --rm -p "${REDIS_PORT}:6379" --name "$CONTAINER_NAME" "$REDIS_IMAGE" >/dev/null
  REDIS_ENDPOINT="127.0.0.1:${REDIS_PORT}"
fi

for _ in {1..50}; do
  if docker exec "$CONTAINER_NAME" redis-cli ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

ROCHE_ARGS=()
if [[ "$ROCHED" == "1" ]]; then
  bin/roched --id=0 --peers="$ROCHED_PEERS" &
  ROCHED_PID="$!"
  sleep 0.3
  ROCHE_ARGS+=(--peers="$ROCHED_PEERS")
fi

bin/rochecli redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  "${ROCHE_ARGS[@]}"
