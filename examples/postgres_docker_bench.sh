#!/usr/bin/env bash
set -euo pipefail

N="${N:-10000}"
PAYLOAD_BYTES="${PAYLOAD_BYTES:-100}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:14}"
ROCHED_IMAGE="${ROCHED_IMAGE:-rochedb-bench:local}"
NETWORK="${NETWORK:-rochedb-postgres-bench-$$}"
PG_CONTAINER="${PG_CONTAINER:-roche-postgres-bench-$$}"
ROCHED_PREFIX="${ROCHED_PREFIX:-roche-pg-roched-$$}"
BUILD_IMAGE="${BUILD_IMAGE:-1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="${ROCHE_BENCH_TMP:-$ROOT/.tmp/rochedb-postgres-docker-bench-$$}"
ROCHE_DATA="$TMP_ROOT/roche"
POSTGRES_DATA="$TMP_ROOT/postgres"
PEERS="${ROCHED_PREFIX}0:17301,${ROCHED_PREFIX}1:17301,${ROCHED_PREFIX}2:17301"

cleanup() {
  docker rm -f "$PG_CONTAINER" "${ROCHED_PREFIX}0" "${ROCHED_PREFIX}1" "${ROCHED_PREFIX}2" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  echo "missing required command: docker" >&2
  exit 127
fi

cd "$ROOT"

if [[ "$BUILD_IMAGE" == "1" ]]; then
  echo "[postgres-docker-bench] build RocheDB image $ROCHED_IMAGE"
  docker build -f examples/compose/Dockerfile -t "$ROCHED_IMAGE" .
fi

cleanup
docker network create "$NETWORK" >/dev/null
mkdir -p "$ROCHE_DATA" "$POSTGRES_DATA"

echo "[postgres-docker-bench] start RocheDB cluster on Docker network $NETWORK"
for id in 0 1 2; do
  mkdir -p "$ROCHE_DATA/node$id"
  docker run -d --rm --network "$NETWORK" --name "${ROCHED_PREFIX}${id}" \
    -v "$ROCHE_DATA/node$id:/data" \
    "$ROCHED_IMAGE" --id="$id" --peers="$PEERS" --slow-tick=0.05 >/dev/null
done

for _ in $(seq 1 50); do
  if docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
    "$ROCHED_IMAGE" health --peers="$PEERS" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
  "$ROCHED_IMAGE" health --peers="$PEERS" >/dev/null

echo "[postgres-docker-bench] RocheDB cluster benchmark"
docker run --rm --network "$NETWORK" --entrypoint /usr/local/bin/rochecli \
  "$ROCHED_IMAGE" bench --peers="$PEERS" --n="$N"

echo "[postgres-docker-bench] start PostgreSQL container"
docker run -d --rm --network "$NETWORK" --name "$PG_CONTAINER" \
  -v "$POSTGRES_DATA:/var/lib/postgresql/data" \
  -e POSTGRES_HOST_AUTH_METHOD=trust "$POSTGRES_IMAGE" >/dev/null

for _ in $(seq 1 80); do
  if docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
docker exec "$PG_CONTAINER" pg_isready -U postgres >/dev/null

if ! docker exec "$PG_CONTAINER" pgbench --version >/dev/null 2>&1; then
  echo "missing pgbench in $POSTGRES_IMAGE; use POSTGRES_IMAGE with pgbench installed" >&2
  exit 127
fi

payload="$(printf "%${PAYLOAD_BYTES}s" "" | tr " " "a")"

docker exec -i "$PG_CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 >/dev/null <<SQL
CREATE TABLE kv (
  k integer PRIMARY KEY,
  v text NOT NULL
);
INSERT INTO kv
SELECT i, repeat('a', $PAYLOAD_BYTES)
FROM generate_series(1, $N) AS s(i);

CREATE TABLE kv_write (
  k integer PRIMARY KEY,
  v text NOT NULL
);
SQL

docker exec -i "$PG_CONTAINER" sh -c 'cat > /tmp/select.sql' <<SQL
\set id random(1, $N)
SELECT v FROM kv WHERE k = :id;
SQL

docker exec -i "$PG_CONTAINER" sh -c 'cat > /tmp/write.sql' <<SQL
\set id random(1, 1000000000)
INSERT INTO kv_write(k, v)
VALUES (:id, '$payload')
ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
SQL

run_pgbench() {
  local out
  if ! out="$(docker exec "$PG_CONTAINER" "$@" 2>&1)"; then
    printf "%s\n" "$out" >&2
    return 1
  fi
  printf "%s\n" "$out" | grep -E \
    "^(pgbench \\(|transaction type:|query mode:|number of clients:|number of threads:|number of transactions|latency average =|tps =)"
}

echo "[postgres-docker-bench] PostgreSQL primary-key SELECT"
run_pgbench pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/select.sql

echo "[postgres-docker-bench] PostgreSQL single-row write, synchronous_commit=off"
run_pgbench env PGOPTIONS="-c synchronous_commit=off" \
  pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/write.sql

echo "[postgres-docker-bench] PostgreSQL single-row write, synchronous_commit=on"
run_pgbench env PGOPTIONS="-c synchronous_commit=on" \
  pgbench -U postgres -d postgres -n -M prepared -c 1 -j 1 -t "$N" -f /tmp/write.sql
