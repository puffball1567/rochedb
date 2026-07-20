#!/usr/bin/env bash
set -euo pipefail

N="${N:-100000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
CONTAINER_NAME="${CONTAINER_NAME:-kouten-redis-bench}"
NETWORK_MODE="${NETWORK_MODE:-host}"
REDIS_PORT="${REDIS_PORT:-6379}"
KOUTEND="${KOUTEND:-0}"
KOUTEND_PEERS="${KOUTEND_PEERS:-127.0.0.1:17301}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p bin
nim c -d:release -o:bin/koutencli src/koutencli.nim
if [[ "$KOUTEND" == "1" ]]; then
  nim c -d:release -o:bin/koutend src/koutend.nim
fi

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  if [[ -n "${KOUTEND_PID:-}" ]]; then
    kill "$KOUTEND_PID" >/dev/null 2>&1 || true
    wait "$KOUTEND_PID" >/dev/null 2>&1 || true
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

KOUTEN_ARGS=()
if [[ "$KOUTEND" == "1" ]]; then
  bin/koutend --id=0 --peers="$KOUTEND_PEERS" &
  KOUTEND_PID="$!"
  sleep 0.3
  KOUTEN_ARGS+=(--peers="$KOUTEND_PEERS")
fi

bin/koutencli redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_ENDPOINT" \
  "${KOUTEN_ARGS[@]}"
