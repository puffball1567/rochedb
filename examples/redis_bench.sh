#!/usr/bin/env bash
set -euo pipefail

N="${N:-100000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
CONTAINER_NAME="${CONTAINER_NAME:-orbelias-redis-bench}"
NETWORK_MODE="${NETWORK_MODE:-host}"
REDIS_PORT="${REDIS_PORT:-6379}"
ORBELIASD="${ORBELIASD:-0}"
ORBELIASD_PEERS="${ORBELIASD_PEERS:-127.0.0.1:17301}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release -o:bin/orbeliascli src/orbeliascli.nim
if [[ "$ORBELIASD" == "1" ]]; then
  nim c -d:release -o:bin/orbeliasd src/orbeliasd.nim
fi

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  if [[ -n "${ORBELIASD_PID:-}" ]]; then
    kill "$ORBELIASD_PID" >/dev/null 2>&1 || true
    wait "$ORBELIASD_PID" >/dev/null 2>&1 || true
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

ORBELIAS_ARGS=()
if [[ "$ORBELIASD" == "1" ]]; then
  bin/orbeliasd --id=0 --peers="$ORBELIASD_PEERS" &
  ORBELIASD_PID="$!"
  sleep 0.3
  ORBELIAS_ARGS+=(--peers="$ORBELIASD_PEERS")
fi

bin/orbeliascli redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  "${ORBELIAS_ARGS[@]}"
