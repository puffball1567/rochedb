#!/usr/bin/env bash
set -euo pipefail

N="${N:-1000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
REDIS_IMAGE="${REDIS_IMAGE:-redis:7-alpine}"
ROCHED_IMAGE="${ROCHED_IMAGE:-rochedb-bench:local}"
NETWORK="${NETWORK:-rochedb-redis-bench-$$}"
REDIS_CONTAINER="${REDIS_CONTAINER:-roche-redis-bench-$$}"
ROCHED_CONTAINER="${ROCHED_CONTAINER:-roche-roched-bench-$$}"
BUILD_IMAGE="${BUILD_IMAGE:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cleanup() {
  docker rm -f "$REDIS_CONTAINER" "$ROCHED_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "missing required command: docker" >&2
  exit 127
fi

cd "$ROOT"

if [[ "$BUILD_IMAGE" == "1" ]]; then
  echo "[redis-docker-bench] build RocheDB image $ROCHED_IMAGE"
  docker build -f examples/compose/Dockerfile -t "$ROCHED_IMAGE" .
fi

cleanup
docker network create "$NETWORK" >/dev/null

echo "[redis-docker-bench] start Redis container"
docker run -d --rm --network "$NETWORK" --name "$REDIS_CONTAINER" "$REDIS_IMAGE" >/dev/null

for _ in $(seq 1 50); do
  if docker exec "$REDIS_CONTAINER" redis-cli ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
docker exec "$REDIS_CONTAINER" redis-cli ping >/dev/null

echo "[redis-docker-bench] start RocheDB container"
docker run -d --rm --network "$NETWORK" --name "$ROCHED_CONTAINER" \
  "$ROCHED_IMAGE" --id=0 --peers=0.0.0.0:17301 >/dev/null

for _ in $(seq 1 50); do
  if docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
    "$ROCHED_IMAGE" health --peers="$ROCHED_CONTAINER:17301" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
  "$ROCHED_IMAGE" health --peers="$ROCHED_CONTAINER:17301" >/dev/null

echo "[redis-docker-bench] run RocheDB/Redis benchmark inside Docker network"
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
  "$ROCHED_IMAGE" redis-bench \
  --n="$N" \
  --payload-bytes="$PAYLOAD_BYTES" \
  --redis="$REDIS_CONTAINER:6379" \
  --peers="$ROCHED_CONTAINER:17301"
